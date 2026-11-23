// Confines a helper before it reads any model file.
//
// A helper parses files of several gigabytes that came from the internet. If
// one of them were built to exploit a bug in a parser, the code it runs would
// have the user's own rights. So a helper gives most of them up at start: it
// keeps what it needs to load a model and compute on the GPU, and no more.
//
// The app starts each helper with `--sandbox <models folder> <scratch folder>`.
// Without that argument the helper is not confined, which is for running one
// by hand while working on it.
#pragma once

#include <sandbox.h>
#include <sys/stat.h>
#include <unistd.h>

#include <climits>
#include <cstdlib>
#include <cstring>
#include <string>

namespace kiln {

// A path as a string literal of the sandbox profile language.
inline std::string sandbox_quote(const std::string& path) {
    std::string quoted = "\"";
    for (char c : path) {
        if (c == '"' || c == '\\') {
            quoted += '\\';
        }
        quoted += c;
    }
    return quoted + "\"";
}

// The sandbox compares paths with symbolic links resolved, such as /private/var for /var.
inline std::string sandbox_real_path(const std::string& path) {
    char resolved[PATH_MAX];
    return realpath(path.c_str(), resolved) != nullptr ? resolved : path;
}

inline std::string sandbox_profile(const std::string& models, const std::string& scratch) {
    std::string writable = "(subpath " + sandbox_quote(sandbox_real_path(scratch)) + ")";
    // Metal keeps compiled shaders in the system's cache folder for this user.
    char cache[PATH_MAX] = "";
    if (confstr(_CS_DARWIN_USER_CACHE_DIR, cache, sizeof(cache)) > 0 && cache[0] != '\0') {
        writable += " (subpath " + sandbox_quote(sandbox_real_path(cache)) + ")";
    }
    return std::string("(version 1)\n") +
        // Everything is allowed except what follows. A list of what a helper may do
        // would be tighter, but Metal's needs are not documented and change between
        // systems; a helper that stops working on a new macOS would be worse.
        "(allow default)\n"
        // No network of any kind.
        "(deny network*)\n"
        // Nothing may be started.
        "(deny process-fork)\n"
        "(deny process-exec*)\n"
        // Nothing in a home folder or on another volume may be read, except the models
        // and the scratch folder. Looking up a path needs the names along it, not
        // what the files hold.
        "(deny file-read* (subpath \"/Users\") (subpath \"/Volumes\"))\n"
        "(allow file-read* (subpath " + sandbox_quote(sandbox_real_path(models)) + ") " + writable + ")\n"
        "(allow file-read-metadata)\n"
        // Nothing may be written, except in the scratch folder and that cache.
        "(deny file-write*)\n"
        "(allow file-write* " + writable + " (literal \"/dev/null\") (literal \"/dev/dtracehelper\"))\n"
        // No talking to other apps.
        "(deny appleevent-send)\n"
        "(deny mach-lookup (global-name \"com.apple.pasteboard.1\")"
        " (global-name \"com.apple.coreservices.launchservicesd\"))\n";
}

// Enters the sandbox when the helper was started with `--sandbox <models> <scratch>`.
// Returns false, with the reason, when it was asked to and could not: the helper
// must then stop instead of running unconfined.
inline bool enter_sandbox(int argc, char** argv, std::string& error) {
    if (argc < 2 || std::strcmp(argv[1], "--sandbox") != 0) {
        return true;
    }
    if (argc < 4) {
        error = "--sandbox needs the models folder and the scratch folder";
        return false;
    }
    // An engine may unpack small files into the temporary folder, as audio.cpp does
    // with what a model file carries inside it. The system's own is outside the
    // sandbox, so the scratch folder stands in for it; it has to exist to be used.
    mkdir(argv[3], 0700);
    setenv("TMPDIR", sandbox_real_path(argv[3]).c_str(), 1);
    const std::string profile = sandbox_profile(argv[2], argv[3]);
    char* message = nullptr;
    // Deprecated since macOS 10.8 without a replacement for a command-line tool;
    // it is what sandbox-exec and other apps' helpers use.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    const int result = sandbox_init(profile.c_str(), 0, &message);
    if (result != 0) {
        error = message != nullptr ? message : "the system refused the sandbox profile";
        if (message != nullptr) {
            sandbox_free_error(message);
        }
    }
#pragma clang diagnostic pop
    return result == 0;
}

}  // namespace kiln
