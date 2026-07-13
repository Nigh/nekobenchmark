#include <SDL3/SDL.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <random>

namespace {

enum class Stage { Ready, Waiting, Go, Summary, Invalid };
enum class Palette { RedGreen, YellowBlue };

struct TestState {
    static constexpr size_t kTrialCount = 5;
    static constexpr Uint64 kTimeoutNs = 1'000'000'000ULL;

    Stage stage{Stage::Ready};
    Palette palette{Palette::RedGreen};
    Uint64 target_time_ns{};
    std::array<Uint64, kTrialCount> reactions_ns{};
    size_t reaction_count{};

    void begin_trial(Uint64 now_ns, Uint64 wait_ns) {
        stage = Stage::Waiting;
        target_time_ns = now_ns + wait_ns;
    }

    void start(Uint64 now_ns, Uint64 wait_ns) {
        reaction_count = 0;
        begin_trial(now_ns, wait_ns);
    }

    void update(Uint64 now_ns) {
        if (stage == Stage::Waiting && now_ns >= target_time_ns) {
            stage = Stage::Go;
        } else if (stage == Stage::Go && now_ns - target_time_ns > kTimeoutNs) {
            stage = Stage::Invalid;
            reaction_count = 0;
        }
    }

    void react(Uint64 event_ns) {
        if (stage == Stage::Waiting) {
            stage = Stage::Invalid;
            reaction_count = 0;
        } else if (stage == Stage::Go) {
            reactions_ns[reaction_count++] = event_ns >= target_time_ns ? event_ns - target_time_ns : 0;
            stage = reaction_count == kTrialCount ? Stage::Summary : Stage::Waiting;
        }
    }
};

struct ReactionStats {
    double median_ms;
    double mean_ms;
    double standard_deviation_ms;
};

float frame_uncertainty_ms(float refresh_hz) {
    return refresh_hz > 0.0f ? 1000.0f / refresh_hz : 0.0f;
}

ReactionStats calculate_stats(const std::array<Uint64, TestState::kTrialCount>& reactions_ns) {
    std::array<Uint64, TestState::kTrialCount> sorted = reactions_ns;
    std::sort(sorted.begin(), sorted.end());

    double sum_ms = 0.0;
    for (const Uint64 reaction_ns : reactions_ns) {
        sum_ms += static_cast<double>(reaction_ns) / 1'000'000.0;
    }
    const double mean_ms = sum_ms / reactions_ns.size();

    double sum_squared_difference = 0.0;
    for (const Uint64 reaction_ns : reactions_ns) {
        const double difference = static_cast<double>(reaction_ns) / 1'000'000.0 - mean_ms;
        sum_squared_difference += difference * difference;
    }
    return {
        static_cast<double>(sorted[sorted.size() / 2]) / 1'000'000.0,
        mean_ms,
        std::sqrt(sum_squared_difference / (reactions_ns.size() - 1)),
    };
}

const char* palette_name(Palette palette) {
    return palette == Palette::RedGreen ? "RED -> GREEN" : "YELLOW -> BLUE";
}

void run_self_check() {
    const auto expect = [](bool condition) {
        if (!condition) {
            std::abort();
        }
    };
    expect(std::abs(frame_uncertainty_ms(60.0f) - (1000.0f / 60.0f)) < 0.001f);
    expect(frame_uncertainty_ms(0.0f) == 0.0f);

    TestState test;
    test.start(100, 50);
    test.react(120);
    expect(test.stage == Stage::Invalid && test.reaction_count == 0);

    test.start(100, 50);
    test.update(150);
    expect(test.stage == Stage::Go);
    test.react(180);
    expect(test.stage == Stage::Waiting && test.reaction_count == 1 && test.reactions_ns[0] == 30);

    test.update(151);
    test.update(151 + TestState::kTimeoutNs + 1);
    expect(test.stage == Stage::Invalid && test.reaction_count == 0);

    const ReactionStats stats = calculate_stats({100'000'000ULL, 200'000'000ULL, 300'000'000ULL,
                                                 400'000'000ULL, 500'000'000ULL});
    expect(std::abs(stats.median_ms - 300.0) < 0.001);
    expect(std::abs(stats.mean_ms - 300.0) < 0.001);
    expect(std::abs(stats.standard_deviation_ms - 158.113883) < 0.001);

    test.palette = Palette::YellowBlue;
    expect(std::strcmp(palette_name(test.palette), "YELLOW -> BLUE") == 0);
}

void set_window_title(SDL_Window* window, const TestState& test, float refresh_hz, int vsync) {
    char title[256];
    const char* stage = "Start a five-trial reaction test";
    if (test.stage == Stage::Waiting) {
        stage = "Wait for the target color...";
    } else if (test.stage == Stage::Go) {
        stage = "CLICK OR PRESS NOW!";
    } else if (test.stage == Stage::Invalid) {
        stage = "Invalid round - restart from trial one";
    } else if (test.stage == Stage::Summary) {
        stage = "Five-trial results - press or click to restart";
    }
    std::snprintf(title, sizeof(title), "NekoBenchmark | %s | %.1f Hz | VSync: %s",
                  stage, refresh_hz, vsync == 0 ? "disabled" : "enabled/unknown");
    SDL_SetWindowTitle(window, title);
}

void draw_text(SDL_Renderer* renderer, float x, float y, const char* text) {
    SDL_RenderDebugText(renderer, x, y, text);
}

void render(SDL_Renderer* renderer, const TestState& test, float refresh_hz, bool vsync_disabled) {
    Uint8 r = 28, g = 31, b = 38;
    if (test.stage == Stage::Waiting) {
        if (test.palette == Palette::RedGreen) {
            r = 210; g = 48; b = 52;
        } else {
            r = 245; g = 197; b = 24;
        }
    } else if (test.stage == Stage::Go) {
        if (test.palette == Palette::RedGreen) {
            r = 35; g = 185; b = 91;
        } else {
            r = 45; g = 116; b = 220;
        }
    }

    SDL_SetRenderDrawColor(renderer, r, g, b, SDL_ALPHA_OPAQUE);
    SDL_RenderClear(renderer);

    const bool bright_background = test.stage == Stage::Waiting || test.stage == Stage::Go;
    SDL_SetRenderDrawColor(renderer, bright_background ? 10 : 235, bright_background ? 14 : 239,
                           bright_background ? 21 : 245, SDL_ALPHA_OPAQUE);
    SDL_SetRenderScale(renderer, 2.0f, 2.0f);

    char line[160];
    draw_text(renderer, 24, 24, "NEKOBENCHMARK - REACTION SPEED");
    std::snprintf(line, sizeof(line), "MODE: %s    [C] CHANGE COLORS", palette_name(test.palette));
    draw_text(renderer, 24, 44, line);

    if (test.stage == Stage::Ready) {
        draw_text(renderer, 24, 86, "PRESS Z, X, SPACE, OR LEFT MOUSE BUTTON TO START");
        draw_text(renderer, 24, 106, "COMPLETE 5 TRIALS. EACH TARGET TIMES OUT AFTER 1 SECOND.");
    } else if (test.stage == Stage::Waiting) {
        std::snprintf(line, sizeof(line), "TRIAL %zu OF %zu - WAIT...", test.reaction_count + 1, TestState::kTrialCount);
        draw_text(renderer, 24, 86, line);
        draw_text(renderer, 24, 106, "DO NOT PRESS OR CLICK YET.");
    } else if (test.stage == Stage::Go) {
        std::snprintf(line, sizeof(line), "TRIAL %zu OF %zu - NOW!", test.reaction_count + 1, TestState::kTrialCount);
        draw_text(renderer, 24, 86, line);
        draw_text(renderer, 24, 106, "RESPOND WITHIN 1 SECOND.");
    } else if (test.stage == Stage::Invalid) {
        draw_text(renderer, 24, 86, "ROUND INVALID: FALSE START OR TIMEOUT");
        draw_text(renderer, 24, 106, "ALL SAMPLES DISCARDED. PRESS OR CLICK TO RESTART AT TRIAL 1.");
    } else {
        const ReactionStats stats = calculate_stats(test.reactions_ns);
        draw_text(renderer, 24, 86, "FIVE-TRIAL RESULTS");
        std::snprintf(line, sizeof(line), "MEDIAN: %.3f ms  |  MEAN: %.3f ms  |  STD DEV: %.3f ms",
                      stats.median_ms, stats.mean_ms, stats.standard_deviation_ms);
        draw_text(renderer, 24, 106, line);
        if (refresh_hz > 0.0f) {
            std::snprintf(line, sizeof(line), "DISPLAY: %.2f Hz  |  FRAME UNCERTAINTY: +/- %.3f ms",
                          refresh_hz, frame_uncertainty_ms(refresh_hz));
        } else {
            std::snprintf(line, sizeof(line), "DISPLAY REFRESH RATE: UNAVAILABLE");
        }
        draw_text(renderer, 24, 126, line);
        draw_text(renderer, 24, 146, "INPUT DEVICE POLLING RATE: NOT MEASURED");
        draw_text(renderer, 24, 166, "PRESS OR CLICK TO START A NEW FIVE-TRIAL ROUND.");
    }

    std::snprintf(line, sizeof(line), "PRESENT: VSync %s (COMPOSITOR MAY STILL SYNCHRONIZE)",
                  vsync_disabled ? "DISABLED" : "NOT DISABLED");
    draw_text(renderer, 24, 232, line);
    draw_text(renderer, 24, 246, "[ESC] QUIT");
    SDL_SetRenderScale(renderer, 1.0f, 1.0f);
    SDL_RenderPresent(renderer);
}

float refresh_rate_for_window(SDL_Window* window) {
    const SDL_DisplayID display = SDL_GetDisplayForWindow(window);
    const SDL_DisplayMode* mode = display ? SDL_GetCurrentDisplayMode(display) : nullptr;
    return mode ? mode->refresh_rate : 0.0f;
}

bool is_reaction_input(const SDL_Event& event) {
    return (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN && event.button.button == SDL_BUTTON_LEFT) ||
           (event.type == SDL_EVENT_KEY_DOWN && !event.key.repeat &&
            (event.key.scancode == SDL_SCANCODE_Z || event.key.scancode == SDL_SCANCODE_X ||
             event.key.scancode == SDL_SCANCODE_SPACE));
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc == 2 && std::strcmp(argv[1], "--self-test") == 0) {
        run_self_check();
        return 0;
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        std::fprintf(stderr, "SDL initialization failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    if (!SDL_CreateWindowAndRenderer("NekoBenchmark", 960, 540, SDL_WINDOW_RESIZABLE,
                                     &window, &renderer)) {
        std::fprintf(stderr, "Window creation failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    const bool requested_immediate = SDL_SetRenderVSync(renderer, SDL_RENDERER_VSYNC_DISABLED);
    int vsync = 1;
    const bool queried_vsync = SDL_GetRenderVSync(renderer, &vsync);
    const bool vsync_disabled = requested_immediate && queried_vsync && vsync == SDL_RENDERER_VSYNC_DISABLED;

    std::random_device random_device;
    std::mt19937_64 random(random_device());
    std::uniform_int_distribution<Uint64> wait_ns(1'000'000'000ULL, 4'000'000'000ULL);

    TestState test;
    bool running = true;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT ||
                (event.type == SDL_EVENT_KEY_DOWN && event.key.scancode == SDL_SCANCODE_ESCAPE)) {
                running = false;
                continue;
            }
            if (event.type == SDL_EVENT_KEY_DOWN && !event.key.repeat && event.key.scancode == SDL_SCANCODE_C) {
                test.palette = test.palette == Palette::RedGreen ? Palette::YellowBlue : Palette::RedGreen;
                continue;
            }
            if (is_reaction_input(event)) {
                const Uint64 timestamp = event.common.timestamp;
                if (test.stage == Stage::Ready || test.stage == Stage::Invalid || test.stage == Stage::Summary) {
                    test.start(timestamp, wait_ns(random));
                } else {
                    test.react(timestamp);
                    if (test.stage == Stage::Waiting) {
                        test.begin_trial(timestamp, wait_ns(random));
                    }
                }
            }
        }

        test.update(SDL_GetTicksNS());
        const float refresh_hz = refresh_rate_for_window(window);
        set_window_title(window, test, refresh_hz, vsync);
        render(renderer, test, refresh_hz, vsync_disabled);
    }

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
