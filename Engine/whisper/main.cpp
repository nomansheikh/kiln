// kiln-whisper: runs whisper.cpp in its own process so a Metal failure cannot
// take the app down. It turns speech into text.
//
// Protocol: one JSON object per line, the same shape kiln-engine uses.
// Requests arrive on stdin, events leave on the original stdout. Library logs
// go to stderr. Closing stdin ends the process.

#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "json.hpp"
#include "whisper.h"

using json = nlohmann::json;

namespace {

int g_event_fd = STDOUT_FILENO;
std::mutex g_event_mutex;

// Only the worker thread touches the context.
whisper_context* g_ctx = nullptr;
std::string g_ctx_path;
std::atomic<bool> g_cancelled{false};

std::mutex g_queue_mutex;
std::condition_variable g_queue_ready;
std::deque<json> g_queue;

void emit(const json& event) {
    std::string line = event.dump(-1, ' ', false, json::error_handler_t::replace);
    line.push_back('\n');
    std::lock_guard<std::mutex> lock(g_event_mutex);
    size_t written = 0;
    while (written < line.size()) {
        ssize_t n = write(g_event_fd, line.data() + written, line.size() - written);
        if (n <= 0) {
            // The app is gone; nothing left to report to.
            _exit(0);
        }
        written += static_cast<size_t>(n);
    }
}

void emit_error(const std::string& code, const std::string& message) {
    emit({{"type", "error"}, {"code", code}, {"message", message}});
}

void on_log(enum ggml_log_level level, const char* text, void*) {
    if (level == GGML_LOG_LEVEL_DEBUG || text == nullptr) {
        return;
    }
    fputs(text, stderr);
}

void on_progress(whisper_context*, whisper_state*, int progress, void*) {
    // whisper.cpp counts in 30-second windows, so a short clip overshoots 100.
    emit({{"type", "progress"}, {"stage", "transcribing"}, {"completed", std::min(progress, 100)}, {"total", 100}});
}

bool should_abort(void*) {
    return g_cancelled;
}

bool load_model(const std::string& path) {
    if (g_ctx != nullptr && path == g_ctx_path) {
        return true;
    }
    emit({{"type", "loading"}});
    if (g_ctx != nullptr) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
        g_ctx_path.clear();
    }
    g_ctx = whisper_init_from_file_with_params(path.c_str(), whisper_context_default_params());
    if (g_ctx == nullptr) {
        emit_error("load_failed", "The model could not be loaded.");
        return false;
    }
    g_ctx_path = path;
    return true;
}

// The app decodes the audio file and hands over raw 32-bit float samples,
// mono, at the 16 kHz whisper.cpp expects.
bool read_samples(const std::string& path, std::vector<float>& samples) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) {
        return false;
    }
    const std::streamsize size = file.tellg();
    if (size <= 0 || size % sizeof(float) != 0) {
        return false;
    }
    samples.resize(static_cast<size_t>(size) / sizeof(float));
    file.seekg(0);
    file.read(reinterpret_cast<char*>(samples.data()), size);
    return file.good();
}

void transcribe(const json& request) {
    if (!load_model(request.at("model").get<std::string>())) {
        return;
    }
    if (g_cancelled) {
        emit({{"type", "cancelled"}});
        return;
    }

    std::vector<float> samples;
    if (!read_samples(request.at("audio").get<std::string>(), samples)) {
        emit_error("invalid_request", "The audio could not be read.");
        return;
    }

    const std::string prompt   = request.value("prompt", std::string());
    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress      = false;
    params.print_realtime      = false;
    params.print_timestamps    = false;
    params.no_timestamps       = true;
    // "auto" makes whisper.cpp detect the spoken language.
    params.language            = "auto";
    params.initial_prompt      = prompt.empty() ? nullptr : prompt.c_str();
    params.progress_callback   = on_progress;
    params.abort_callback      = should_abort;

    const int status = whisper_full(g_ctx, params, samples.data(), static_cast<int>(samples.size()));
    if (g_cancelled) {
        emit({{"type", "cancelled"}});
        return;
    }
    if (status != 0) {
        emit_error("generation_failed", "The audio could not be transcribed.");
        return;
    }

    std::string text;
    const int segments = whisper_full_n_segments(g_ctx);
    for (int i = 0; i < segments; i++) {
        const char* segment = whisper_full_get_segment_text(g_ctx, i);
        if (segment != nullptr) {
            text += segment;
        }
    }

    const std::string output = request.at("output").get<std::string>();
    std::ofstream file(output, std::ios::binary | std::ios::trunc);
    file << text;
    file.close();
    if (file.good()) {
        emit({{"type", "text"}, {"path", output}});
    } else {
        emit_error("write_failed", "The text could not be written to " + output + ".");
    }
}

void worker() {
    for (;;) {
        json request;
        {
            std::unique_lock<std::mutex> lock(g_queue_mutex);
            g_queue_ready.wait(lock, [] { return !g_queue.empty(); });
            request = std::move(g_queue.front());
            g_queue.pop_front();
        }
        try {
            transcribe(request);
        } catch (const std::exception& e) {
            emit_error("invalid_request", e.what());
        }
        emit({{"type", "idle"}});
    }
}

}  // namespace

int main() {
    // Anything the libraries print to stdout would corrupt the event stream,
    // so events keep the real stdout and fd 1 is pointed at stderr.
    g_event_fd = dup(STDOUT_FILENO);
    dup2(STDERR_FILENO, STDOUT_FILENO);

    whisper_log_set(on_log, nullptr);
    emit({{"type", "ready"}, {"version", whisper_version()}, {"commit", ""}});

    std::thread(worker).detach();

    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) {
            continue;
        }
        json request = json::parse(line, nullptr, false);
        if (request.is_discarded() || !request.is_object()) {
            emit_error("invalid_request", "The request is not a JSON object.");
            continue;
        }
        const std::string type = request.value("type", std::string());
        if (type == "transcribe") {
            g_cancelled = false;
            std::lock_guard<std::mutex> lock(g_queue_mutex);
            g_queue.push_back(std::move(request));
            g_queue_ready.notify_one();
        } else if (type == "cancel") {
            g_cancelled = true;
        } else {
            emit_error("invalid_request", "Unknown request type \"" + type + "\".");
        }
    }
    _exit(0);
}
