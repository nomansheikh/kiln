// kiln-audio: runs audio.cpp in its own process so a Metal failure cannot take
// the app down. It turns text into speech.
//
// Protocol: one JSON object per line, the same shape kiln-engine uses.
// Requests arrive on stdin, events leave on the original stdout. Library logs
// go to stderr. Closing stdin ends the process.

#include <unistd.h>

#include <condition_variable>
#include <cstdio>
#include <deque>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "audiocpp.h"
#include "json.hpp"
#include "../sandbox.h"

using json = nlohmann::json;

namespace {

int g_event_fd = STDOUT_FILENO;
std::mutex g_event_mutex;

// Only the worker thread touches the registry, the model and the session.
audiocpp_registry* g_registry = nullptr;
audiocpp_model* g_model       = nullptr;
audiocpp_session* g_session   = nullptr;
std::string g_loaded_key;

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

// Reports a failed library call, with the library's own explanation for the log.
bool failed(audiocpp_status status, const char* code, const char* message) {
    if (status == AUDIOCPP_OK) {
        return false;
    }
    fprintf(stderr, "[error] %s\n", audiocpp_last_error());
    emit_error(code, message);
    return true;
}

void unload() {
    audiocpp_session_free(g_session);
    audiocpp_model_free(g_model);
    g_session = nullptr;
    g_model   = nullptr;
    g_loaded_key.clear();
}

// `copies_voice` is true for a request that brings a recording of the voice to speak in.
bool load_model(const std::string& path, const std::string& family, const std::string& backend_name, bool copies_voice) {
    const std::string key = family + "\n" + path + "\n" + backend_name + (copies_voice ? "\nclone" : "");
    if (g_session != nullptr && key == g_loaded_key) {
        return true;
    }
    emit({{"type", "loading"}});
    unload();

    if (g_registry == nullptr &&
        failed(audiocpp_registry_create(nullptr, &g_registry), "load_failed", "The engine could not be started.")) {
        return false;
    }
    const audiocpp_model_config config = {family.empty() ? nullptr : family.c_str(), nullptr, nullptr, nullptr};
    if (failed(audiocpp_model_load(g_registry, path.c_str(), &config, nullptr, &g_model), "load_failed",
               "The model could not be loaded.")) {
        unload();
        return false;
    }
    const audiocpp_backend_config backend = {backend_name.c_str(), 0, 4};
    // Copying a voice is a task of its own in the models that have one; the others
    // take the recording on an ordinary request.
    const char* task = copies_voice && audiocpp_model_supports(g_model, "clon", "offline") == 1 ? "clon" : "tts";
    if (failed(audiocpp_session_create(g_model, task, "offline", &backend, nullptr, &g_session), "load_failed",
               "The model could not be loaded.")) {
        unload();
        return false;
    }
    g_loaded_key = key;
    return true;
}

void speak(const json& request) {
    // The GPU unless the app asks for the CPU, which it does for a model that fails on the GPU.
    // A recording of the voice to speak in: raw mono 32-bit floats, as the app decodes them.
    std::vector<float> voice_samples;
    const std::string voice_audio = request.value("voice_audio", std::string());
    const int voice_rate          = request.value("voice_sample_rate", 0);
    if (!voice_audio.empty()) {
        std::ifstream file(voice_audio, std::ios::binary | std::ios::ate);
        const std::streamoff size = file ? static_cast<std::streamoff>(file.tellg()) : 0;
        if (size < static_cast<std::streamoff>(sizeof(float)) || voice_rate <= 0) {
            emit_error("invalid_request", "The voice recording could not be read.");
            return;
        }
        voice_samples.resize(static_cast<size_t>(size) / sizeof(float));
        file.seekg(0);
        file.read(reinterpret_cast<char*>(voice_samples.data()),
                  static_cast<std::streamsize>(voice_samples.size() * sizeof(float)));
    }

    if (!load_model(request.at("model").get<std::string>(), request.value("family", std::string()),
                    request.value("backend", std::string("metal")), !voice_samples.empty())) {
        return;
    }

    const std::string text     = request.at("text").get<std::string>();
    const std::string language = request.value("language", std::string());
    const std::string voice    = request.value("voice", std::string());

    audiocpp_request* speech = audiocpp_request_create();
    audiocpp_status status   = audiocpp_request_set_text(speech, text.c_str(), language.empty() ? nullptr : language.c_str());
    if (status == AUDIOCPP_OK && !voice_samples.empty()) {
        status = audiocpp_request_set_voice_audio(speech, voice_samples.data(), voice_samples.size(), voice_rate, 1);
    } else if (status == AUDIOCPP_OK && !voice.empty()) {
        status = audiocpp_request_set_voice_id(speech, voice.c_str());
    }
    // Model-specific settings, such as a seed, by the names audio.cpp gives them.
    if (request.contains("options") && request.at("options").is_object()) {
        for (const auto& [name, value] : request.at("options").items()) {
            if (status == AUDIOCPP_OK && value.is_string()) {
                status = audiocpp_request_set_option(speech, name.c_str(), value.get<std::string>().c_str());
            }
        }
    }
    if (failed(status, "invalid_request", "The request could not be prepared.")) {
        audiocpp_request_free(speech);
        return;
    }

    emit({{"type", "progress"}, {"stage", "speaking"}, {"completed", 0}, {"total", 0}});
    audiocpp_result* result = nullptr;
    status                  = audiocpp_session_run(g_session, speech, &result);
    audiocpp_request_free(speech);
    if (failed(status, "generation_failed", "The speech could not be generated.")) {
        audiocpp_result_free(result);
        return;
    }

    const float* samples = nullptr;
    size_t frames        = 0;
    int sample_rate      = 0;
    int channels         = 0;
    if (audiocpp_result_audio(result, &samples, &frames, &sample_rate, &channels) != AUDIOCPP_OK || samples == nullptr ||
        frames == 0 || sample_rate <= 0 || channels <= 0) {
        emit_error("generation_failed", "The model produced no audio.");
        audiocpp_result_free(result);
        return;
    }

    // Raw interleaved 32-bit floats; the app turns them into an audio file.
    const std::string output = request.at("output").get<std::string>();
    std::ofstream file(output, std::ios::binary | std::ios::trunc);
    file.write(reinterpret_cast<const char*>(samples),
               static_cast<std::streamsize>(frames * static_cast<size_t>(channels) * sizeof(float)));
    file.close();
    if (file.good()) {
        emit({{"type", "audio"}, {"path", output}, {"sample_rate", sample_rate}, {"channels", channels}, {"frames", frames}});
    } else {
        emit_error("write_failed", "The audio could not be written to " + output + ".");
    }
    audiocpp_result_free(result);
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
            speak(request);
        } catch (const std::exception& e) {
            emit_error("invalid_request", e.what());
        }
        emit({{"type", "idle"}});
    }
}

}  // namespace

int main(int argc, char** argv) {
    // Before anything else: give up every right this helper does not need.
    std::string sandbox_error;
    if (!kiln::enter_sandbox(argc, argv, sandbox_error)) {
        std::fprintf(stderr, "[error] could not enter the sandbox: %s\n", sandbox_error.c_str());
        return 1;
    }

    // Anything the libraries print to stdout would corrupt the event stream,
    // so events keep the real stdout and fd 1 is pointed at stderr.
    g_event_fd = dup(STDOUT_FILENO);
    dup2(STDERR_FILENO, STDOUT_FILENO);

    emit({{"type", "ready"}, {"version", audiocpp_build_version()}, {"commit", ""}});

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
        if (type == "speak") {
            std::lock_guard<std::mutex> lock(g_queue_mutex);
            g_queue.push_back(std::move(request));
            g_queue_ready.notify_one();
        } else if (type == "cancel") {
            // audio.cpp cannot stop a run in progress. The app ends the helper
            // when a cancelled job does not stop in time.
        } else {
            emit_error("invalid_request", "Unknown request type \"" + type + "\".");
        }
    }
    _exit(0);
}
