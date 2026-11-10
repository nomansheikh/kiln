// kiln-engine: runs stable-diffusion.cpp in its own process so a Metal failure
// cannot take the app down.
//
// Protocol: one JSON object per line. Requests arrive on stdin, events leave
// on the original stdout. Library logs go to stderr. Closing stdin ends the
// process.

#include <unistd.h>

#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "json.hpp"
#include "stable-diffusion.h"

using json = nlohmann::json;

namespace {

int g_event_fd = STDOUT_FILENO;
std::mutex g_event_mutex;

// Guards g_ctx against a cancel request racing a model swap.
std::mutex g_ctx_mutex;
sd_ctx_t* g_ctx = nullptr;
std::string g_ctx_key;
std::atomic<bool> g_generating{false};
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

void on_log(enum sd_log_level_t level, const char* text, void*) {
    static const char* names[] = {"debug", "verbose", "info", "warn", "error"};
    if (level < SD_LOG_INFO || text == nullptr) {
        return;
    }
    fprintf(stderr, "[%s] %s", names[level], text);
    size_t length = strlen(text);
    if (length == 0 || text[length - 1] != '\n') {
        fputc('\n', stderr);
    }
}

void on_progress(const sd_generation_progress_t* progress, void*) {
    emit({{"type", "progress"},
          {"stage", progress->stage ? progress->stage : ""},
          {"detail", progress->detail ? progress->detail : ""},
          {"completed", progress->completed},
          {"total", progress->total}});
}

const char* optional_path(const json& model, const char* key, std::string& storage) {
    storage = model.value(key, std::string());
    return storage.empty() ? nullptr : storage.c_str();
}

bool load_model(const json& model) {
    const std::string key = model.dump();
    if (g_ctx != nullptr && key == g_ctx_key) {
        return true;
    }

    emit({{"type", "loading"}});
    {
        std::lock_guard<std::mutex> lock(g_ctx_mutex);
        if (g_ctx != nullptr) {
            free_sd_ctx(g_ctx);
            g_ctx = nullptr;
            g_ctx_key.clear();
        }
    }

    std::string checkpoint, diffusion_model, llm, vae;
    sd_ctx_params_t params;
    sd_ctx_params_init(&params);
    params.model_path           = optional_path(model, "checkpoint", checkpoint);
    params.diffusion_model_path = optional_path(model, "diffusion_model", diffusion_model);
    params.llm_path             = optional_path(model, "llm", llm);
    params.vae_path             = optional_path(model, "vae", vae);
    params.diffusion_flash_attn = model.value("flash_attention", false);

    sd_ctx_t* ctx = new_sd_ctx(&params);
    if (ctx == nullptr) {
        emit_error("load_failed", "The model could not be loaded.");
        return false;
    }
    sd_set_generation_progress_callback(ctx, on_progress, nullptr);

    std::lock_guard<std::mutex> lock(g_ctx_mutex);
    g_ctx     = ctx;
    g_ctx_key = key;
    return true;
}

bool write_pixels(const std::string& path, const sd_image_t& image) {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    if (!file) {
        return false;
    }
    const size_t size = static_cast<size_t>(image.width) * image.height * image.channel;
    file.write(reinterpret_cast<const char*>(image.data), static_cast<std::streamsize>(size));
    return file.good();
}

void generate(const json& request) {
    const json& params = request.at("params");

    if (!load_model(request.at("model"))) {
        return;
    }
    if (g_cancelled) {
        emit({{"type", "cancelled"}});
        return;
    }

    const std::string prompt          = params.value("prompt", std::string());
    const std::string negative_prompt = params.value("negative_prompt", std::string());
    std::vector<float> sigmas         = params.value("sigmas", std::vector<float>());

    sd_img_gen_params_t gen;
    sd_img_gen_params_init(&gen);
    gen.prompt          = prompt.c_str();
    gen.negative_prompt = negative_prompt.c_str();
    gen.width           = params.at("width").get<int>();
    gen.height          = params.at("height").get<int>();
    gen.seed            = params.at("seed").get<int64_t>();
    gen.batch_count     = 1;

    gen.sample_params.sample_steps     = params.at("steps").get<int>();
    gen.sample_params.guidance.txt_cfg = params.at("cfg").get<float>();

    const std::string sampler = params.value("sampler", std::string());
    if (sampler.empty()) {
        gen.sample_params.sample_method = sd_get_default_sample_method(g_ctx);
    } else {
        gen.sample_params.sample_method = str_to_sample_method(sampler.c_str());
        if (gen.sample_params.sample_method == SAMPLE_METHOD_COUNT) {
            emit_error("invalid_request", "Unknown sampler \"" + sampler + "\".");
            return;
        }
    }
    gen.sample_params.scheduler = sd_get_default_scheduler(g_ctx, gen.sample_params.sample_method);
    if (!sigmas.empty()) {
        gen.sample_params.custom_sigmas       = sigmas.data();
        gen.sample_params.custom_sigmas_count = static_cast<int>(sigmas.size());
    }

    sd_cancel_generation(g_ctx, SD_CANCEL_RESET);
    g_generating = true;
    // A cancel that arrived while the model was loading had no context to act on.
    if (g_cancelled) {
        sd_cancel_generation(g_ctx, SD_CANCEL_ALL);
    }
    sd_image_generation_result_t* result = nullptr;
    const bool ok                        = generate_image(g_ctx, &gen, &result);
    g_generating                         = false;

    if (g_cancelled) {
        if (result != nullptr) {
            free_sd_image_generation_result(result);
        }
        emit({{"type", "cancelled"}});
        return;
    }
    if (!ok || result == nullptr || result->count < 1 || result->items[0].image.data == nullptr) {
        if (result != nullptr) {
            free_sd_image_generation_result(result);
        }
        emit_error("generation_failed", "The engine did not produce an image.");
        return;
    }

    const sd_image_t& image  = result->items[0].image;
    const std::string output = request.at("output").get<std::string>();
    if (write_pixels(output, image)) {
        emit({{"type", "image"},
              {"path", output},
              {"width", image.width},
              {"height", image.height},
              {"channels", image.channel}});
    } else {
        emit_error("write_failed", "The image could not be written to " + output + ".");
    }
    free_sd_image_generation_result(result);
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
            generate(request);
        } catch (const std::exception& e) {
            emit_error("invalid_request", e.what());
        }
        emit({{"type", "idle"}});
    }
}

void cancel() {
    g_cancelled = true;
    std::lock_guard<std::mutex> lock(g_ctx_mutex);
    if (g_ctx != nullptr && g_generating) {
        sd_cancel_generation(g_ctx, SD_CANCEL_ALL);
    }
}

}  // namespace

int main() {
    // Anything the libraries print to stdout would corrupt the event stream,
    // so events keep the real stdout and fd 1 is pointed at stderr.
    g_event_fd = dup(STDOUT_FILENO);
    dup2(STDERR_FILENO, STDOUT_FILENO);

    sd_set_log_callback(on_log, nullptr);
    emit({{"type", "ready"}, {"version", sd_version()}, {"commit", sd_commit()}});

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
        if (type == "generate") {
            g_cancelled = false;
            std::lock_guard<std::mutex> lock(g_queue_mutex);
            g_queue.push_back(std::move(request));
            g_queue_ready.notify_one();
        } else if (type == "cancel") {
            cancel();
        } else {
            emit_error("invalid_request", "Unknown request type \"" + type + "\".");
        }
    }
    _exit(0);
}
