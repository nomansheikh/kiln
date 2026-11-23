// kiln-trellis: runs trellis.cpp in its own process so a Metal failure cannot
// take the app down. It turns one image into a 3D object, saved as a GLB file.
//
// Protocol: one JSON object per line, the same shape kiln-engine uses.
// Requests arrive on stdin, events leave on the original stdout. Library logs
// go to stderr. Closing stdin ends the process.

#include <unistd.h>

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

#include "json.hpp"
#include "trellis_run.h"
#include "../sandbox.h"

using json = nlohmann::json;

namespace {

int g_event_fd = STDOUT_FILENO;
std::mutex g_event_mutex;
std::atomic<bool> g_running{false};

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

// trellis.cpp reports what it is doing only by printing lines such as
// "[4/7] shape SLAT flow (512)" and "[flow] [###...]  3/12  12.1s", so those
// are read back and turned into progress events.
// The two are folded into one count: each step is worth kStepUnits, and a
// step that samples fills its own share as it goes.
const int kStepUnits = 12;
int g_step = 0;
int g_steps = 7;

void report(const std::string& line) {
    int first = 0;
    int second = 0;
    if (std::sscanf(line.c_str(), "[%d/%d]", &first, &second) == 2 && first >= 1 && second >= first) {
        g_step = first;
        g_steps = second;
        emit({{"type", "progress"}, {"stage", "step"}, {"completed", (first - 1) * kStepUnits}, {"total", second * kStepUnits}});
        return;
    }
    const size_t flow = line.find("[flow]");
    const size_t bar = flow == std::string::npos ? std::string::npos : line.find(']', flow + 6);
    if (g_step >= 1 && bar != std::string::npos && std::sscanf(line.c_str() + bar + 1, " %d/%d", &first, &second) == 2 &&
        second > 0 && first <= second) {
        emit({{"type", "progress"}, {"stage", "step"},
              {"completed", (g_step - 1) * kStepUnits + first * kStepUnits / second}, {"total", g_steps * kStepUnits}});
    }
}

// Everything the library prints to stdout comes through this pipe: it is looked
// at for progress and then passed on to stderr with the other logs.
void forward_output(int read_fd) {
    std::string pending;
    char buffer[4096];
    for (;;) {
        const ssize_t n = read(read_fd, buffer, sizeof(buffer));
        if (n <= 0) {
            return;
        }
        (void)!write(STDERR_FILENO, buffer, static_cast<size_t>(n));
        pending.append(buffer, static_cast<size_t>(n));
        size_t end = 0;
        // The step counter redraws its line with a carriage return.
        while ((end = pending.find_first_of("\r\n")) != std::string::npos) {
            const std::string line = pending.substr(0, end);
            pending.erase(0, end + 1);
            if (!line.empty()) {
                report(line);
            }
        }
    }
}

void shape(const json& request) {
    trellis::TrellisParams params;
    params.models = request.at("models").get<std::string>();
    params.image  = request.at("image").get<std::string>();
    params.output = request.at("output").get<std::string>();
    params.seed   = request.value("seed", 0u);
    // 512 is the light path; 1024 and 1536 refine a 512 result.
    params.set_res(request.value("resolution", 1024));
    params.steps = request.value("steps", 0);
    params.gss   = request.value("structure_guidance", params.gss);
    params.gsh   = request.value("shape_guidance", params.gsh);
    const std::string cutout = request.value("cutout", std::string("auto"));
    params.birefnet = cutout == "birefnet" ? 1 : cutout == "threshold" ? 0 : -1;
    const int texture_size = request.value("texture_size", 0);
    if (texture_size > 0) {
        params.tex = texture_size;
    }
    // PNG textures, which macOS reads; see CMakeLists.txt.
    params.webp = 0;
    // The CPU path takes hours and far more memory, so failing is the better answer.
    params.require_gpu = true;

    g_step = 0;
    int status = 1;
    try {
        status = trellis_run(params);
    } catch (const std::exception& e) {
        emit_error("generation_failed", e.what());
        return;
    }
    fflush(stdout);
    std::ifstream written(params.output, std::ios::binary);
    if (status != 0 || !written.good()) {
        emit_error("generation_failed", "The 3D object could not be made.");
        return;
    }
    emit({{"type", "object"}, {"path", params.output}});
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
        g_running = true;
        try {
            shape(request);
        } catch (const std::exception& e) {
            emit_error("invalid_request", e.what());
        }
        g_running = false;
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

    // Events keep the real stdout. What the library prints there is read back
    // through a pipe, for the progress it carries.
    g_event_fd = dup(STDOUT_FILENO);
    int output_pipe[2];
    if (pipe(output_pipe) != 0) {
        std::fprintf(stderr, "[error] could not open a pipe for the engine's output\n");
        return 1;
    }
    dup2(output_pipe[1], STDOUT_FILENO);
    close(output_pipe[1]);
    setvbuf(stdout, nullptr, _IONBF, 0);
    std::thread(forward_output, output_pipe[0]).detach();

    emit({{"type", "ready"}, {"version", "trellis.cpp"}, {"commit", ""}});

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
        if (type == "shape") {
            std::lock_guard<std::mutex> lock(g_queue_mutex);
            g_queue.push_back(std::move(request));
            g_queue_ready.notify_one();
        } else if (type == "cancel") {
            // trellis.cpp cannot be asked to stop part-way, so stopping ends the
            // process. Nothing is lost: it loads each model anew for every run.
            if (g_running) {
                emit({{"type", "cancelled"}});
                _exit(0);
            }
        } else {
            emit_error("invalid_request", "Unknown request type \"" + type + "\".");
        }
    }
    _exit(0);
}
