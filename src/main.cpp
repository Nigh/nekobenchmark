#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <numbers>
#include <random>
#include <string>
#include <unordered_map>
#include <utility>

namespace {

enum class Stage { Ready, Waiting, Go, Summary, Invalid, AwaitingNextTrial };
enum class Palette { RedGreen, YellowBlue };
enum class Language { English, Chinese };

struct TestState {
    static constexpr size_t kTrialCount = 5;
    static constexpr Uint64 kTimeoutNs = 1'000'000'000ULL;

    Stage stage{Stage::Ready};
    Palette palette{Palette::RedGreen};
    Language language{Language::English};
    bool reverse_color_order{};
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

    void schedule_next_trial(Uint64 now_ns, Uint64 wait_ns, bool require_key_press) {
        if (require_key_press) {
            stage = Stage::AwaitingNextTrial;
        } else {
            begin_trial(now_ns, wait_ns);
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

const char* localized(Language language, const char* english, const char* chinese) {
    return language == Language::Chinese ? chinese : english;
}

const char* stage_name(Stage stage, Language language) {
    if (language == Language::Chinese) {
        switch (stage) {
        case Stage::Ready: return "开始五次反应测试";
        case Stage::Waiting: return "等待目标颜色...";
        case Stage::Go: return "立即按键或点击！";
        case Stage::Summary: return "五次测试结果 - 按键或点击重新开始";
        case Stage::Invalid: return "本轮无效 - 从第一次重新开始";
        case Stage::AwaitingNextTrial: return "按键开始下一次测试";
        }
    }
    switch (stage) {
    case Stage::Ready: return "Start a five-trial reaction test";
    case Stage::Waiting: return "Wait for the target color...";
    case Stage::Go: return "CLICK OR PRESS NOW!";
    case Stage::Summary: return "Five-trial results - press or click to restart";
    case Stage::Invalid: return "Invalid round - restart from trial one";
    case Stage::AwaitingNextTrial: return "Press a key to begin the next trial";
    }
    return "";
}

bool is_reaction_key(SDL_Scancode scancode) {
    return scancode == SDL_SCANCODE_Z || scancode == SDL_SCANCODE_X ||
           scancode == SDL_SCANCODE_SPACE || scancode == SDL_SCANCODE_UP ||
           scancode == SDL_SCANCODE_DOWN || scancode == SDL_SCANCODE_LEFT ||
           scancode == SDL_SCANCODE_RIGHT;
}

bool held_for_trigger(Uint64 pressed_ns, Uint64 released_ns) {
    return pressed_ns != 0 && released_ns >= pressed_ns &&
           released_ns - pressed_ns >= TestState::kTimeoutNs;
}

void set_window_title(SDL_Window* window, float refresh_hz, int vsync) {
    char title[256];
    std::snprintf(title, sizeof(title), "NekoBenchmark | %.1f Hz | VSync: %s", refresh_hz,
                  vsync == 0 ? "disabled" : "enabled/unknown");
    SDL_SetWindowTitle(window, title);
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
    test.schedule_next_trial(180, 50, true);
    expect(test.stage == Stage::AwaitingNextTrial && test.reaction_count == 1);
    test.begin_trial(190, 50);
    expect(test.stage == Stage::Waiting && test.reaction_count == 1);

    test.update(240);
    test.update(240 + TestState::kTimeoutNs + 1);
    expect(test.stage == Stage::Invalid && test.reaction_count == 0);

    const ReactionStats stats = calculate_stats({100'000'000ULL, 200'000'000ULL, 300'000'000ULL,
                                                 400'000'000ULL, 500'000'000ULL});
    expect(std::abs(stats.median_ms - 300.0) < 0.001);
    expect(std::abs(stats.mean_ms - 300.0) < 0.001);
    expect(std::abs(stats.standard_deviation_ms - 158.113883) < 0.001);

    test.palette = Palette::YellowBlue;
    expect(std::strcmp(palette_name(test.palette), "YELLOW -> BLUE") == 0);
    test.reverse_color_order = true;
    expect(test.reverse_color_order);
    test.language = Language::Chinese;
    expect(std::strcmp(stage_name(Stage::Go, test.language), "立即按键或点击！") == 0);
    expect(is_reaction_key(SDL_SCANCODE_UP));
    expect(is_reaction_key(SDL_SCANCODE_DOWN));
    expect(is_reaction_key(SDL_SCANCODE_LEFT));
    expect(is_reaction_key(SDL_SCANCODE_RIGHT));
    expect(!is_reaction_key(SDL_SCANCODE_A));
    expect(held_for_trigger(100, 100 + TestState::kTimeoutNs));
    expect(!held_for_trigger(100, 100 + TestState::kTimeoutNs - 1));
}

struct TextCache {
    struct Entry {
        SDL_Texture* texture{};
        float width{};
        float height{};
    };
    struct Metrics {
        float width{};
        float height{};
    };
    TextCache(std::string latin_font_path, std::string cjk_font_path)
        : latin_font_path_(std::move(latin_font_path)), cjk_font_path_(std::move(cjk_font_path)) {}

    void draw_centered(SDL_Renderer* renderer, const char* text, float center_x, float y, float point_size,
                       SDL_Color color) {
        const Entry* entry = get(renderer, text, point_size, color);
        if (entry == nullptr) {
            return;
        }
        const SDL_FRect destination{center_x - entry->width / 2.0f, y, entry->width, entry->height};
        SDL_RenderTexture(renderer, entry->texture, nullptr, &destination);
    }

    void warm(SDL_Renderer* renderer, const char* text, float point_size, SDL_Color color) {
        get(renderer, text, point_size, color);
    }

    Metrics measure(SDL_Renderer* renderer, const char* text, float point_size, SDL_Color color) {
        const Entry* entry = get(renderer, text, point_size, color);
        return entry == nullptr ? Metrics{} : Metrics{entry->width, entry->height};
    }

    void clear() {
        for (auto& [_, entry] : entries_) {
            SDL_DestroyTexture(entry.texture);
        }
        for (auto& [_, font] : fonts_) {
            TTF_CloseFont(font);
        }
        entries_.clear();
        fonts_.clear();
    }

    ~TextCache() { clear(); }

  private:
    const Entry* get(SDL_Renderer* renderer, const char* text, float point_size, SDL_Color color) {
        const std::string key = std::to_string(point_size) + ":" + std::to_string(color.r) + ":" +
                                std::to_string(color.g) + ":" + std::to_string(color.b) + ":" + text;
        if (const auto existing = entries_.find(key); existing != entries_.end()) {
            return &existing->second;
        }

        const int size = static_cast<int>(point_size);
        const bool use_cjk_font = std::any_of(text, text + std::strlen(text),
                                              [](unsigned char character) { return character >= 0xE3; });
        const std::string font_key = (use_cjk_font ? "cjk:" : "latin:") + std::to_string(size);
        TTF_Font*& font = fonts_[font_key];
        if (font == nullptr) {
            font = TTF_OpenFont((use_cjk_font ? cjk_font_path_ : latin_font_path_).c_str(), point_size);
        }
        if (font == nullptr) {
            return nullptr;
        }
        SDL_Surface* surface = TTF_RenderText_Blended(font, text, 0, color);
        if (surface == nullptr) {
            return nullptr;
        }
        SDL_Texture* texture = SDL_CreateTextureFromSurface(renderer, surface);
        SDL_DestroySurface(surface);
        if (texture == nullptr) {
            return nullptr;
        }

        float width{};
        float height{};
        SDL_GetTextureSize(texture, &width, &height);
        return &entries_.emplace(key, Entry{texture, width, height}).first->second;
    }

    std::string latin_font_path_;
    std::string cjk_font_path_;
    std::unordered_map<std::string, Entry> entries_;
    std::unordered_map<std::string, TTF_Font*> fonts_;
};

constexpr SDL_Color kInk{235, 240, 249, SDL_ALPHA_OPAQUE};
constexpr SDL_Color kMuted{151, 166, 189, SDL_ALPHA_OPAQUE};
constexpr SDL_Color kAccent{119, 144, 255, SDL_ALPHA_OPAQUE};

void fill_rect(SDL_Renderer* renderer, SDL_FRect rect, SDL_Color color) {
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_RenderFillRect(renderer, &rect);
}

void fill_rounded_rect(SDL_Renderer* renderer, SDL_FRect rect, float radius, SDL_Color color) {
    radius = std::min(radius, std::min(rect.w, rect.h) / 2.0f);
    const int pixel_radius = static_cast<int>(std::ceil(radius));
    if (pixel_radius == 0) {
        fill_rect(renderer, rect, color);
        return;
    }

    // Each pixel row is filled exactly once. Overlapping translucent rectangles
    // would otherwise make the center of a card visibly darker.
    fill_rect(renderer, {rect.x, rect.y + pixel_radius, rect.w, rect.h - pixel_radius * 2.0f}, color);
    for (int offset = 0; offset < pixel_radius; ++offset) {
        const float distance = pixel_radius - static_cast<float>(offset) - 0.5f;
        const float inset =
            pixel_radius - std::sqrt(std::max(0.0f, static_cast<float>(pixel_radius * pixel_radius) - distance * distance));
        const float row_width = rect.w - inset * 2.0f;
        fill_rect(renderer, {rect.x + inset, rect.y + static_cast<float>(offset), row_width, 1.0f}, color);
        fill_rect(renderer, {rect.x + inset, rect.y + rect.h - static_cast<float>(offset) - 1.0f, row_width, 1.0f},
                  color);
    }
}

void draw_rounded_outline(SDL_Renderer* renderer, SDL_FRect rect, float radius, SDL_Color color) {
    const int pixel_radius = static_cast<int>(std::ceil(std::min(radius, std::min(rect.w, rect.h) / 2.0f)));
    if (pixel_radius == 0) {
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
        SDL_RenderRect(renderer, &rect);
        return;
    }

    fill_rect(renderer, {rect.x + pixel_radius, rect.y, rect.w - pixel_radius * 2.0f, 1.0f}, color);
    fill_rect(renderer, {rect.x + pixel_radius, rect.y + rect.h - 1.0f, rect.w - pixel_radius * 2.0f, 1.0f}, color);
    fill_rect(renderer, {rect.x, rect.y + pixel_radius, 1.0f, rect.h - pixel_radius * 2.0f}, color);
    fill_rect(renderer, {rect.x + rect.w - 1.0f, rect.y + pixel_radius, 1.0f, rect.h - pixel_radius * 2.0f}, color);

    int previous_inset = pixel_radius;
    for (int offset = 0; offset < pixel_radius; ++offset) {
        const float distance = pixel_radius - static_cast<float>(offset) - 0.5f;
        const int inset = static_cast<int>(pixel_radius -
                                           std::sqrt(std::max(0.0f, static_cast<float>(pixel_radius * pixel_radius) -
                                                                       distance * distance)));
        const float segment_width = static_cast<float>(std::max(1, previous_inset - inset + 1));
        const float left_x = rect.x + inset;
        const float right_x = rect.x + rect.w - inset - segment_width;
        for (const float y : {rect.y + static_cast<float>(offset), rect.y + rect.h - static_cast<float>(offset) - 1.0f}) {
            fill_rect(renderer, {left_x, y, segment_width, 1.0f}, color);
            fill_rect(renderer, {right_x, y, segment_width, 1.0f}, color);
        }
        previous_inset = inset;
    }
}

void draw_card(SDL_Renderer* renderer, SDL_FRect rect, SDL_Color fill, SDL_Color border, float radius = 16.0f) {
    fill_rounded_rect(renderer, rect, radius, fill);
    draw_rounded_outline(renderer, rect, radius, border);
}

void draw_keycap(SDL_Renderer* renderer, TextCache& text, const char* label, float center_x, float y, float width,
                 SDL_Color foreground, SDL_Color fill, SDL_Color border) {
    draw_card(renderer, {center_x - width / 2.0f, y, width, 27.0f}, fill, border, 7.0f);
    text.draw_centered(renderer, label, center_x, y + 6.0f, 12.0f, foreground);
}

void draw_color_swatch(SDL_Renderer* renderer, SDL_FRect rect, SDL_Color color, SDL_Color border) {
    draw_card(renderer, rect, color, border, 5.0f);
}

void draw_progress(SDL_Renderer* renderer, const TestState& test, float center_x, float y) {
    constexpr float kDotSize = 11.0f;
    constexpr float kGap = 8.0f;
    const float start_x = center_x - (TestState::kTrialCount * kDotSize +
                                      (TestState::kTrialCount - 1) * kGap) / 2.0f;
    for (size_t index = 0; index < TestState::kTrialCount; ++index) {
        const bool complete = index < test.reaction_count;
        const bool active = index == test.reaction_count && test.stage != Stage::Summary;
        fill_rect(renderer, {start_x + index * (kDotSize + kGap), y, kDotSize, kDotSize},
                  complete ? kAccent : active ? kInk : SDL_Color{55, 68, 93, SDL_ALPHA_OPAQUE});
    }
}

void render(SDL_Renderer* renderer, TextCache& text, const TestState& test, float refresh_hz,
            bool vsync_disabled) {
    const bool target_visible = test.stage == Stage::Waiting || test.stage == Stage::Go;
    const SDL_Color palette_start =
        test.palette == Palette::RedGreen ? SDL_Color{186, 53, 62, SDL_ALPHA_OPAQUE}
                                          : SDL_Color{228, 177, 27, SDL_ALPHA_OPAQUE};
    const SDL_Color palette_end =
        test.palette == Palette::RedGreen ? SDL_Color{33, 170, 94, SDL_ALPHA_OPAQUE}
                                          : SDL_Color{48, 111, 215, SDL_ALPHA_OPAQUE};
    const SDL_Color start_color = test.reverse_color_order ? palette_end : palette_start;
    const SDL_Color end_color = test.reverse_color_order ? palette_start : palette_end;
    SDL_Color background{11, 16, 30, SDL_ALPHA_OPAQUE};
    if (test.stage == Stage::Waiting) {
        background = start_color;
    } else if (test.stage == Stage::Go) {
        background = end_color;
    }
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
    fill_rect(renderer, {0.0f, 0.0f, 10000.0f, 10000.0f}, background);

    int width{};
    int height{};
    SDL_GetRenderOutputSize(renderer, &width, &height);
    const float center_x = width / 2.0f;
    const float card_width = std::min(760.0f, static_cast<float>(width) - 48.0f);
    const float card_x = center_x - card_width / 2.0f;
    const SDL_Color foreground = target_visible ? SDL_Color{255, 255, 255, SDL_ALPHA_OPAQUE} : kInk;
    const SDL_Color soft_foreground = target_visible ? SDL_Color{239, 245, 255, SDL_ALPHA_OPAQUE} : kMuted;
    const SDL_Color card_fill = target_visible ? SDL_Color{7, 17, 34, 104} : SDL_Color{22, 30, 49, SDL_ALPHA_OPAQUE};
    const SDL_Color card_border =
        target_visible ? SDL_Color{255, 255, 255, 108} : SDL_Color{57, 72, 101, SDL_ALPHA_OPAQUE};

    text.draw_centered(renderer, "NEKO / BENCHMARK", center_x, 20.0f, 17.0f, foreground);
    draw_card(renderer, {center_x - 185.0f, 48.0f, 370.0f, 38.0f},
              target_visible ? SDL_Color{7, 17, 34, 82} : SDL_Color{18, 26, 44, SDL_ALPHA_OPAQUE}, card_border, 11.0f);
    const char* palette_start_name = test.palette == Palette::RedGreen
                                 ? localized(test.language, "RED", "红")
                                 : localized(test.language, "YELLOW", "黄");
    const char* palette_end_name = test.palette == Palette::RedGreen
                               ? localized(test.language, "GREEN", "绿")
                               : localized(test.language, "BLUE", "蓝");
    const char* start_name = test.reverse_color_order ? palette_end_name : palette_start_name;
    const char* end_name = test.reverse_color_order ? palette_start_name : palette_end_name;
    text.draw_centered(renderer, start_name, center_x - 106.0f, 60.0f, 12.0f, foreground);
    draw_color_swatch(renderer, {center_x - 76.0f, 59.0f, 18.0f, 18.0f}, start_color, foreground);
    text.draw_centered(renderer, "→", center_x, 59.0f, 16.0f, soft_foreground);
    draw_color_swatch(renderer, {center_x + 56.0f, 59.0f, 18.0f, 18.0f}, end_color, foreground);
    text.draw_centered(renderer, end_name, center_x + 108.0f, 60.0f, 12.0f, foreground);
    text.draw_centered(renderer, vsync_disabled
                                     ? localized(test.language, "IMMEDIATE PRESENT", "立即呈现")
                                     : localized(test.language, "PRESENT UNCONFIRMED", "呈现状态未知"),
                       center_x, 91.0f, 11.0f, soft_foreground);

    if (test.stage == Stage::Summary) {
        const float median_width = std::min(420.0f, card_width);
        draw_card(renderer, {center_x - median_width / 2.0f, 108.0f, median_width, 140.0f}, card_fill, card_border);
        const ReactionStats stats = calculate_stats(test.reactions_ns);
        char median_line[160];
        char mean_line[160];
        char deviation_line[160];
        char display_line[160];
        std::snprintf(median_line, sizeof(median_line), "%.1f ms", stats.median_ms);
        std::snprintf(mean_line, sizeof(mean_line), "%.1f ms", stats.mean_ms);
        std::snprintf(deviation_line, sizeof(deviation_line), "%.1f ms", stats.standard_deviation_ms);
        if (refresh_hz > 0.0f) {
            std::snprintf(display_line, sizeof(display_line), "%.0f Hz  ·  ±%.2f ms", refresh_hz,
                          frame_uncertainty_ms(refresh_hz));
        } else {
            std::snprintf(display_line, sizeof(display_line), "%s",
                          localized(test.language, "REFRESH RATE UNAVAILABLE", "刷新率不可用"));
        }

        constexpr float kResultGap = 7.0f;
        const char* result_title = localized(test.language, "FIVE-TRIAL RESULT", "五次测试结果");
        const char* median_label = localized(test.language, "MEDIAN REACTION TIME", "反应时间中位数");
        const auto title_metrics = text.measure(renderer, result_title, 15.0f, kMuted);
        const auto median_metrics = text.measure(renderer, median_line, 54.0f, kInk);
        const auto median_label_metrics = text.measure(renderer, median_label, 13.0f, kAccent);
        float result_y = 178.0f -
                         (title_metrics.height + median_metrics.height + median_label_metrics.height + kResultGap * 2.0f) /
                             2.0f;
        text.draw_centered(renderer, result_title, center_x, result_y, 15.0f, kMuted);
        result_y += title_metrics.height + kResultGap;
        text.draw_centered(renderer, median_line, center_x, result_y, 54.0f, kInk);
        result_y += median_metrics.height + kResultGap;
        text.draw_centered(renderer, median_label, center_x, result_y, 13.0f, kAccent);

        const float gap = 12.0f;
        const float column_width = (card_width - gap * 2.0f) / 3.0f;
        const float metric_y = 270.0f;
        draw_card(renderer, {card_x, metric_y, column_width, 104.0f}, card_fill, card_border);
        draw_card(renderer, {card_x + column_width + gap, metric_y, column_width, 104.0f}, card_fill, card_border);
        draw_card(renderer, {card_x + (column_width + gap) * 2.0f, metric_y, column_width, 104.0f}, card_fill, card_border);

        constexpr float kMetricGap = 8.0f;
        const float metric_center_y = metric_y + 52.0f;
        const auto mean_metrics = text.measure(renderer, mean_line, 21.0f, kInk);
        const char* mean_label = localized(test.language, "MEAN", "平均值");
        const auto mean_label_metrics = text.measure(renderer, mean_label, 12.0f, kMuted);
        float mean_y = metric_center_y - (mean_metrics.height + kMetricGap + mean_label_metrics.height) / 2.0f;
        text.draw_centered(renderer, mean_line, card_x + column_width * 0.5f, mean_y, 21.0f, kInk);
        text.draw_centered(renderer, mean_label, card_x + column_width * 0.5f, mean_y + mean_metrics.height + kMetricGap,
                           12.0f, kMuted);

        const auto deviation_metrics = text.measure(renderer, deviation_line, 21.0f, kInk);
        const char* deviation_label = localized(test.language, "STD DEV", "标准差");
        const auto deviation_label_metrics = text.measure(renderer, deviation_label, 12.0f, kMuted);
        float deviation_y =
            metric_center_y - (deviation_metrics.height + kMetricGap + deviation_label_metrics.height) / 2.0f;
        text.draw_centered(renderer, deviation_line, card_x + column_width * 1.5f + gap, deviation_y, 21.0f, kInk);
        text.draw_centered(renderer, deviation_label, card_x + column_width * 1.5f + gap,
                           deviation_y + deviation_metrics.height + kMetricGap, 12.0f, kMuted);

        const auto display_metrics = text.measure(renderer, display_line, 16.0f, kInk);
        const char* display_label = localized(test.language, "DISPLAY ERROR", "显示误差");
        const auto display_label_metrics = text.measure(renderer, display_label, 12.0f, kMuted);
        float display_y =
            metric_center_y - (display_metrics.height + kMetricGap + display_label_metrics.height) / 2.0f;
        text.draw_centered(renderer, display_line, card_x + column_width * 2.5f + gap * 2.0f, display_y, 16.0f, kInk);
        text.draw_centered(renderer, display_label, card_x + column_width * 2.5f + gap * 2.0f,
                           display_y + display_metrics.height + kMetricGap, 12.0f, kMuted);
        draw_card(renderer, {center_x - 258.0f, 396.0f, 516.0f, 49.0f}, card_fill, card_border, 12.0f);
        text.draw_centered(renderer, localized(test.language, "Press [Z], [X], [Space], or [LMB] to try again",
                                                "按 [Z]、[X]、[空格] 或 [鼠标左键] 再试一次"),
                           center_x, 412.0f, 13.0f, kMuted);
    } else {
        draw_card(renderer, {center_x - 250.0f, 116.0f, 500.0f, 142.0f}, card_fill, card_border);
        if (test.stage == Stage::Ready) {
            text.draw_centered(renderer, localized(test.language, "REACTION SPEED", "反应速度"), center_x, 165.0f, 29.0f,
                               kInk);
            text.draw_centered(renderer,
                               localized(test.language, "Five precise trials. One second to respond.",
                                         "连续五次测试，每次须在一秒内作答。"),
                               center_x, 211.0f, 16.0f, kMuted);
            draw_card(renderer, {center_x - 206.0f, 278.0f, 412.0f, 57.0f}, card_fill, card_border, 12.0f);
            draw_keycap(renderer, text, "Z", center_x - 126.0f, 293.0f, 32.0f, kAccent, SDL_Color{34, 44, 70, SDL_ALPHA_OPAQUE}, kAccent);
            draw_keycap(renderer, text, "X", center_x - 76.0f, 293.0f, 32.0f, kAccent, SDL_Color{34, 44, 70, SDL_ALPHA_OPAQUE}, kAccent);
            draw_keycap(renderer, text, "SPACE", center_x + 1.0f, 293.0f, 72.0f, kAccent, SDL_Color{34, 44, 70, SDL_ALPHA_OPAQUE}, kAccent);
            draw_keycap(renderer, text, "LMB", center_x + 78.0f, 293.0f, 48.0f, kAccent, SDL_Color{34, 44, 70, SDL_ALPHA_OPAQUE}, kAccent);
            text.draw_centered(renderer, localized(test.language, "BEGIN", "开始"), center_x + 151.0f, 299.0f, 13.0f,
                               kAccent);
        } else if (test.stage == Stage::Waiting) {
            text.draw_centered(renderer, localized(test.language, "WAIT", "等待"), center_x, 145.0f, 42.0f, kInk);
            text.draw_centered(renderer, localized(test.language, "Do not press or click yet.", "请勿按键或点击。"), center_x,
                               205.0f, 17.0f, soft_foreground);
            const float phase = static_cast<float>(SDL_GetTicksNS() % 1'200'000'000ULL) / 1'200'000'000.0f;
            for (int index = 0; index < 3; ++index) {
                const float pulse = (std::sin((phase + index / 3.0f) * 2.0f * std::numbers::pi_v<float>) + 1.0f) / 2.0f;
                const Uint8 alpha = static_cast<Uint8>(80.0f + pulse * 175.0f);
                fill_rect(renderer, {center_x - 16.0f + index * 16.0f, 230.0f, 8.0f, 8.0f},
                          SDL_Color{end_color.r, end_color.g, end_color.b, alpha});
            }
        } else if (test.stage == Stage::Go) {
            text.draw_centered(renderer, localized(test.language, "NOW", "现在"), center_x, 145.0f, 42.0f, kInk);
            text.draw_centered(renderer, localized(test.language, "PRESS OR CLICK", "立即按键或点击"), center_x, 205.0f, 17.0f,
                               soft_foreground);
        } else if (test.stage == Stage::AwaitingNextTrial) {
            text.draw_centered(renderer, localized(test.language, "NEXT TRIAL", "下一次测试"), center_x, 155.0f, 30.0f, kInk);
            text.draw_centered(renderer, localized(test.language, "Press a key to begin when ready.", "准备好后按键开始。"),
                               center_x, 205.0f, 17.0f, kMuted);
        } else {
            text.draw_centered(renderer, localized(test.language, "ROUND INVALID", "本轮无效"), center_x, 155.0f, 30.0f, kInk);
            text.draw_centered(renderer,
                               localized(test.language, "False start or timeout. Your samples were discarded.",
                                         "误触或超时，已清空本轮数据。"),
                               center_x, 205.0f, 15.0f, kMuted);
            draw_card(renderer, {center_x - 200.0f, 278.0f, 400.0f, 57.0f}, card_fill, card_border, 12.0f);
            text.draw_centered(renderer, localized(test.language, "PRESS [Z], [X], [SPACE], OR [LMB]",
                                                    "按 [Z]、[X]、[空格] 或 [鼠标左键]"),
                               center_x, 298.0f, 14.0f, kAccent);
        }
        draw_card(renderer, {center_x - 168.0f, 360.0f, 336.0f, 61.0f}, card_fill, card_border, 12.0f);
        draw_progress(renderer, test, center_x, 383.0f);
    }

    const float footer_y = static_cast<float>(height) - 42.0f;
    draw_keycap(renderer, text, "C", center_x - 180.0f, footer_y, 30.0f, soft_foreground,
                target_visible ? SDL_Color{7, 17, 34, 104} : SDL_Color{26, 35, 56, SDL_ALPHA_OPAQUE}, card_border);
    text.draw_centered(renderer, localized(test.language, "CHANGE COLORS", "切换配色"), center_x - 110.0f, footer_y + 7.0f,
                       12.0f, soft_foreground);
    draw_keycap(renderer, text, "V", center_x - 20.0f, footer_y, 30.0f, soft_foreground,
                target_visible ? SDL_Color{7, 17, 34, 104} : SDL_Color{26, 35, 56, SDL_ALPHA_OPAQUE}, card_border);
    text.draw_centered(renderer, localized(test.language, "REVERSE ORDER", "反转顺序"), center_x + 40.0f, footer_y + 7.0f,
                       12.0f, soft_foreground);
    draw_keycap(renderer, text, "ESC", center_x + 145.0f, footer_y, 42.0f, soft_foreground,
                target_visible ? SDL_Color{7, 17, 34, 104} : SDL_Color{26, 35, 56, SDL_ALPHA_OPAQUE}, card_border);
    text.draw_centered(renderer, localized(test.language, "QUIT", "退出"), center_x + 190.0f, footer_y + 7.0f, 12.0f,
                       soft_foreground);
    SDL_RenderPresent(renderer);
}

float refresh_rate_for_window(SDL_Window* window) {
    const SDL_DisplayID display = SDL_GetDisplayForWindow(window);
    const SDL_DisplayMode* mode = display ? SDL_GetCurrentDisplayMode(display) : nullptr;
    return mode ? mode->refresh_rate : 0.0f;
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
    if (!TTF_Init()) {
        std::fprintf(stderr, "SDL_ttf initialization failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    if (!SDL_CreateWindowAndRenderer("NekoBenchmark", 960, 540, SDL_WINDOW_RESIZABLE,
                                     &window, &renderer)) {
        std::fprintf(stderr, "Window creation failed: %s\n", SDL_GetError());
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    const char* base_path = SDL_GetBasePath();
    const std::string latin_font_path = base_path != nullptr ? std::string(base_path) + "MapleMono-Regular.ttf"
                                                             : "MapleMono-Regular.ttf";
    const std::string cjk_font_path = base_path != nullptr ? std::string(base_path) + "NotoSansCJKsc-Regular.otf"
                                                           : "NotoSansCJKsc-Regular.otf";
    TTF_Font* verification_font = TTF_OpenFont(latin_font_path.c_str(), 16.0f);
    if (verification_font == nullptr) {
        std::fprintf(stderr, "Could not load bundled Maple Mono font: %s\n", SDL_GetError());
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }
    TTF_CloseFont(verification_font);
    verification_font = TTF_OpenFont(cjk_font_path.c_str(), 16.0f);
    if (verification_font == nullptr) {
        std::fprintf(stderr, "Could not load bundled Noto Sans CJK font: %s\n", SDL_GetError());
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }
    TTF_CloseFont(verification_font);
    TextCache text(latin_font_path, cjk_font_path);

    const bool requested_immediate = SDL_SetRenderVSync(renderer, SDL_RENDERER_VSYNC_DISABLED);
    int vsync = 1;
    const bool queried_vsync = SDL_GetRenderVSync(renderer, &vsync);
    const bool vsync_disabled = requested_immediate && queried_vsync && vsync == SDL_RENDERER_VSYNC_DISABLED;
    // Pre-render every target-state string. The first target color must not be
    // delayed by font rasterization or texture uploads.
    constexpr SDL_Color kTargetInk{255, 255, 255, SDL_ALPHA_OPAQUE};
    constexpr SDL_Color kTargetMuted{239, 245, 255, SDL_ALPHA_OPAQUE};
    for (const Language language : {Language::English, Language::Chinese}) {
        text.warm(renderer, "NEKO / BENCHMARK", 17.0f, kTargetInk);
        text.warm(renderer, localized(language, "WAIT", "等待"), 42.0f, kTargetInk);
        text.warm(renderer, localized(language, "NOW", "现在"), 42.0f, kTargetInk);
        text.warm(renderer, localized(language, "Do not press or click yet.", "请勿按键或点击。"), 17.0f, kTargetMuted);
        text.warm(renderer, localized(language, "PRESS OR CLICK", "立即按键或点击"), 17.0f, kTargetMuted);
    }

    std::random_device random_device;
    std::mt19937_64 random(random_device());
    std::uniform_int_distribution<Uint64> wait_ns(1'000'000'000ULL, 4'000'000'000ULL);

    TestState test;
    std::array<Uint64, SDL_SCANCODE_COUNT> key_down_ns{};
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
            if (event.type == SDL_EVENT_KEY_DOWN && !event.key.repeat && event.key.scancode == SDL_SCANCODE_V) {
                test.reverse_color_order = !test.reverse_color_order;
                continue;
            }
            if (event.type == SDL_EVENT_KEY_DOWN && !event.key.repeat && event.key.scancode == SDL_SCANCODE_L) {
                test.language = test.language == Language::English ? Language::Chinese : Language::English;
                continue;
            }

            const auto trigger_reaction = [&](Uint64 timestamp, bool release_trigger) {
                if (test.stage == Stage::Ready || test.stage == Stage::Invalid || test.stage == Stage::Summary) {
                    test.start(timestamp, wait_ns(random));
                } else if (test.stage == Stage::AwaitingNextTrial) {
                    test.begin_trial(timestamp, wait_ns(random));
                } else {
                    test.react(timestamp);
                    if (test.stage == Stage::Waiting) {
                        test.schedule_next_trial(timestamp, wait_ns(random), release_trigger);
                    }
                }
            };

            if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN && event.button.button == SDL_BUTTON_LEFT) {
                trigger_reaction(event.common.timestamp, false);
            } else if (event.type == SDL_EVENT_KEY_DOWN && !event.key.repeat && is_reaction_key(event.key.scancode)) {
                key_down_ns[static_cast<size_t>(event.key.scancode)] = event.common.timestamp;
                trigger_reaction(event.common.timestamp, false);
            } else if (event.type == SDL_EVENT_KEY_UP && is_reaction_key(event.key.scancode)) {
                Uint64& pressed_ns = key_down_ns[static_cast<size_t>(event.key.scancode)];
                if (held_for_trigger(pressed_ns, event.common.timestamp)) {
                    trigger_reaction(event.common.timestamp, true);
                }
                pressed_ns = 0;
            }
        }

        test.update(SDL_GetTicksNS());
        const float refresh_hz = refresh_rate_for_window(window);
        set_window_title(window, refresh_hz, vsync);
        render(renderer, text, test, refresh_hz, vsync_disabled);
    }

    text.clear();
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    TTF_Quit();
    SDL_Quit();
    return 0;
}
