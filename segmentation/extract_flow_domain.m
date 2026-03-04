function [flow_domain, solid_mask] = extract_flow_domain(ref_image, chip_mask)
% EXTRACT_FLOW_DOMAIN  Generate binary pore-space mask from a reference image.
%
%   [flow_domain, solid_mask] = extract_flow_domain(ref_image)
%   [flow_domain, solid_mask] = extract_flow_domain(ref_image, chip_mask)
%
%   Detection strategy (in priority order):
%     1. Lab color-based: Uses a* channel to detect DNAPL (pink).
%        Pillars = bright non-DNAPL pixels. Best with DNAPL-saturated frame.
%     2. Morphological fallback: Multi-scale top-hat/bottom-hat.
%        Used when reference has no color contrast (clean/water image).
%
%   Inputs:
%       ref_image   - M x N x 3 uint8 RGB image (preprocessed)
%       chip_mask   - (optional) M x N logical mask defining chip interior.
%
%   Outputs:
%       flow_domain - M x N logical (1 = pore space, 0 = solid)
%       solid_mask  - M x N logical (1 = solid pillar, 0 = pore)

    [H, W, ~] = size(ref_image);

    %% Detection parameters (named constants)
    P.MIN_PILLAR_FRAC      = 0.03;   % below this, detection likely failed
    P.MAX_PILLAR_FRAC      = 0.70;   % above this, detection likely failed
    P.MORPH_RADII          = [3, 5, 8, 10, 15, 20, 25, 30, 40, 50];
    P.MIN_BLOB_AREA_COLOR  = 2;      % color method (minimal to catch tiny pillars)
    P.MIN_BLOB_AREA_MORPH  = 3;      % morphological method (minimal to catch tiny pillars)
    P.MAX_PILLAR_AREA_FRAC = 0.05;   % max single-pillar area as fraction of chip
    P.QUANTILE_RANGE       = 65:2:98;
    P.TARGET_PILLAR_FRAC   = 0.18;
    P.QUANTILE_MIN_FRAC    = 0.05;
    P.QUANTILE_MAX_FRAC    = 0.45;
    P.OTSU_MIN_FRAC        = 0.05;
    P.OTSU_MAX_FRAC        = 0.60;
    P.BRIGHT_MIN_FRAC      = 0.08;
    P.BRIGHT_MAX_FRAC      = 0.55;
    P.MORPH_CONTRAST_MIN   = 0.003;  % minimum morphological contrast
    P.WARN_PILLAR_FRAC     = 0.05;   % warn if below this

    %% Step 1: Determine chip interior
    if nargin >= 2 && ~isempty(chip_mask)
        chip_interior = logical(chip_mask);
        fprintf('  Using user-provided chip mask (%d pixels)\n', sum(chip_interior(:)));
    else
        gray = rgb2gray(ref_image);
        level = graythresh(gray);
        auto_mask = imbinarize(gray, level * 0.85);
        auto_mask = imclose(auto_mask, strel('disk', 15));
        auto_mask = imfill(auto_mask, 'holes');
        auto_mask = bwareaopen(auto_mask, round(H * W * 0.01));

        cc = bwconncomp(auto_mask);
        if cc.NumObjects > 1
            sizes = cellfun(@numel, cc.PixelIdxList);
            [~, idx] = max(sizes);
            auto_mask = false(H, W);
            auto_mask(cc.PixelIdxList{idx}) = true;
        end
        auto_mask = imfill(auto_mask, 'holes');
        chip_interior = imerode(auto_mask, strel('disk', 5));
    end

    if sum(chip_interior(:)) < 100
        solid_mask = false(H, W);
        flow_domain = chip_interior;
        fprintf('  Flow domain: chip too small\n');
        return;
    end

    total_chip = sum(chip_interior(:));

    %% Step 2: Check for DNAPL color in Lab space
    lab = rgb2lab(ref_image);
    L_ch = lab(:,:,1);   % Lightness [0, 100]
    a_ch = lab(:,:,2);   % green-red axis; positive = red/pink

    a_vals = a_ch(chip_interior);
    a_range = prctile(a_vals, 95) - prctile(a_vals, 5);

    fprintf('  Lab a* stats: range=%.1f, p5=%.1f, p95=%.1f, median=%.1f\n', ...
        a_range, prctile(a_vals, 5), prctile(a_vals, 95), median(a_vals));

    if a_range > 5
        solid_mask = detect_pillars_color(a_ch, L_ch, chip_interior, total_chip, P);
        color_frac = sum(solid_mask(:)) / max(total_chip, 1);

        % Guardrail: if color segmentation is implausible, try morphological fallback.
        if color_frac < P.MIN_PILLAR_FRAC || color_frac > P.MAX_PILLAR_FRAC
            fprintf('  Color-based result %.1f%% is implausible. Trying morphological fallback...\n', ...
                color_frac * 100);
            solid_mask_morph = detect_pillars_morphological(ref_image, chip_interior, total_chip, P);
            morph_frac = sum(solid_mask_morph(:)) / max(total_chip, 1);

            if (morph_frac >= P.MIN_PILLAR_FRAC && morph_frac <= P.MAX_PILLAR_FRAC) || ...
                    (color_frac < P.MIN_PILLAR_FRAC && morph_frac > color_frac + 0.01 && morph_frac < 0.85)
                solid_mask = solid_mask_morph;
                fprintf('  Using morphological fallback result: %.1f%% pillars\n', ...
                    morph_frac * 100);
            else
                fprintf('  Keeping color-based result (fallback=%.1f%% not better)\n', ...
                    morph_frac * 100);
            end
        end
    else
        fprintf('  Low color contrast (a* range=%.1f). Using morphological method.\n', a_range);
        solid_mask = detect_pillars_morphological(ref_image, chip_interior, total_chip, P);
    end

    %% Build flow domain
    flow_domain = chip_interior & ~solid_mask;

    %% Report
    pillar_fraction = sum(solid_mask(:)) / max(total_chip, 1);
    porosity = 1 - pillar_fraction;

    fprintf('  Flow domain: %d x %d\n', H, W);
    fprintf('  Pillars: %d pixels (%.1f%% of chip)\n', ...
        sum(solid_mask(:)), pillar_fraction * 100);
    fprintf('  Porosity: %.1f%%\n', porosity * 100);

    if pillar_fraction < P.WARN_PILLAR_FRAC
        fprintf('  WARNING: pillar fraction very low.\n');
        fprintf('    Use a DNAPL-saturated frame (flow_domain_frame = 1) for best results.\n');
    end

    %% Diagnostic figure
    fig_diag = figure('Name', 'Flow Domain Extraction - Diagnostics', ...
        'Position', [50 50 1500 700], 'Color', 'w');

    subplot(2,3,1);
    imshow(ref_image);
    title('Input to extract\_flow\_domain', 'FontSize', 11);

    subplot(2,3,2);
    imagesc(a_ch); colormap(gca, 'jet'); colorbar;
    hold on;
    boundary = bwperim(chip_interior);
    [yy, xx] = find(boundary);
    if ~isempty(xx)
        plot(xx, yy, 'w.', 'MarkerSize', 1);
    end
    title(sprintf('Lab a* (range=%.1f)', a_range), 'FontSize', 11);
    axis image off;

    subplot(2,3,3);
    histogram(a_vals, 100);
    xlabel('a* value'); ylabel('Count');
    title('a* distribution (chip only)', 'FontSize', 11);

    subplot(2,3,4);
    imshow(chip_interior);
    title(sprintf('chip\\_interior (%d px)', sum(chip_interior(:))), 'FontSize', 11);

    subplot(2,3,5);
    imshow(solid_mask);
    title(sprintf('solid\\_mask (%d px, %.1f%%)', ...
        sum(solid_mask(:)), pillar_fraction*100), 'FontSize', 11);

    subplot(2,3,6);
    overlay = im2double(ref_image);
    for c = 1:3
        ch = overlay(:,:,c);
        ch(solid_mask) = (c == 1);  % red for pillars
        overlay(:,:,c) = ch;
    end
    imshow(overlay);
    title(sprintf('Pillars (red) | porosity=%.1f%%', porosity*100), 'FontSize', 11);

    if a_range > 5
        method_str = sprintf('Lab color (a* range=%.1f)', a_range);
    else
        method_str = sprintf('morphological (a* range=%.1f)', a_range);
    end
    sgtitle(['Flow Domain Diagnostics — method: ' method_str], ...
        'FontSize', 14, 'FontWeight', 'bold');
end


%% ========================================================================
%  COLOR-BASED PILLAR DETECTION (Lab a* channel)
%  ========================================================================
function solid_mask = detect_pillars_color(a_ch, L_ch, chip_interior, total_chip, P)
    fprintf('  Using Lab a* color-based pillar detection\n');
    [H, W] = size(a_ch);

    % Otsu on a* within chip to separate DNAPL (high a*) from non-DNAPL
    a_chip = a_ch(chip_interior);
    a_min = min(a_chip);
    a_max = max(a_chip);
    a_norm = (a_chip - a_min) / (a_max - a_min);
    a_thresh = graythresh(uint8(a_norm * 255)) * (a_max - a_min) + a_min;

    fprintf('  a* Otsu threshold: %.1f\n', a_thresh);

    % DNAPL = high a* (pink), non-DNAPL = low a* (pillars + water)
    dnapl_region = (a_ch > a_thresh) & chip_interior;
    non_dnapl = (~dnapl_region) & chip_interior;

    dnapl_frac = sum(dnapl_region(:)) / total_chip;
    non_dnapl_frac = sum(non_dnapl(:)) / total_chip;
    fprintf('  DNAPL: %.1f%%, non-DNAPL: %.1f%%\n', dnapl_frac * 100, non_dnapl_frac * 100);

    % Among non-DNAPL pixels, use L* to separate bright pillars from water
    L_non_dnapl = L_ch(non_dnapl);

    if numel(L_non_dnapl) > 100
        % Otsu on L* to split bright pillars from dimmer water
        L_norm = (L_non_dnapl - min(L_non_dnapl)) / max(max(L_non_dnapl) - min(L_non_dnapl), 1);
        L_thresh_rel = graythresh(uint8(L_norm * 255));
        L_thresh = L_thresh_rel * (max(L_non_dnapl) - min(L_non_dnapl)) + min(L_non_dnapl);

        pillar_cand = non_dnapl & (L_ch > L_thresh);
        pillar_frac_bright = sum(pillar_cand(:)) / total_chip;

        fprintf('  L* threshold: %.1f, bright pillars: %.1f%% of chip\n', ...
            L_thresh, pillar_frac_bright * 100);

        % If bright pillars are plausible (10-50%), use them
        if pillar_frac_bright > P.BRIGHT_MIN_FRAC && pillar_frac_bright < P.BRIGHT_MAX_FRAC
            fprintf('  Using bright-pillar method\n');
        else
            fprintf('  Bright-pillar fraction not plausible (%.1f%%). ', pillar_frac_bright * 100);
            [q_mask, q_frac, q_thresh] = select_bright_quantile_mask(L_ch, non_dnapl, total_chip, P);
            if ~isempty(q_mask)
                pillar_cand = q_mask;
                fprintf('Using quantile fallback (L*=%.1f, %.1f%% of chip).\n', ...
                    q_thresh, q_frac * 100);
            else
                fprintf('Using all non-DNAPL as provisional pillars.\n');
                pillar_cand = non_dnapl;
            end
        end
    else
        pillar_cand = non_dnapl;
        fprintf('  Very few non-DNAPL pixels; treating all as pillars\n');
    end

    % Morphological cleanup
    pillar_cand = imclose(pillar_cand, strel('disk', 2));
    pillar_cand = imopen(pillar_cand, strel('disk', 1));  % radius=1 to preserve small pillars
    pillar_cand = bwareaopen(pillar_cand, P.MIN_BLOB_AREA_COLOR);
    pillar_cand = imfill(pillar_cand, 'holes');

    % Filter individual connected components by area
    max_pillar_area = total_chip * P.MAX_PILLAR_AREA_FRAC;
    stats = regionprops(pillar_cand, 'Area', 'PixelIdxList');
    solid_mask = false(H, W);
    for k = 1:numel(stats)
        a = stats(k).Area;
        if a > P.MIN_BLOB_AREA_COLOR && a < max_pillar_area
            solid_mask(stats(k).PixelIdxList) = true;
        end
    end

    pillar_fraction = sum(solid_mask(:)) / total_chip;
    fprintf('  Color-based result: %.1f%% pillars\n', pillar_fraction * 100);
end


function [best_mask, best_frac, best_thresh] = select_bright_quantile_mask(L_ch, non_dnapl, total_chip, P)
% Select a robust bright subset of non-DNAPL pixels when Otsu on L* is unstable.
    best_mask = [];
    best_frac = 0;
    best_thresh = NaN;

    L_vals = L_ch(non_dnapl);
    if numel(L_vals) < 100
        return;
    end

    best_score = inf;

    for q = P.QUANTILE_RANGE
        th = prctile(L_vals, q);
        cand = non_dnapl & (L_ch > th);
        frac = sum(cand(:)) / max(total_chip, 1);

        if frac >= P.QUANTILE_MIN_FRAC && frac <= P.QUANTILE_MAX_FRAC
            score = abs(frac - P.TARGET_PILLAR_FRAC);
            if score < best_score
                best_score = score;
                best_mask = cand;
                best_frac = frac;
                best_thresh = th;
            end
        end
    end
end


%% ========================================================================
%  MORPHOLOGICAL PILLAR DETECTION (grayscale fallback)
%  ========================================================================
function solid_mask = detect_pillars_morphological(ref_image, chip_interior, total_chip, P)
    fprintf('  Using multi-scale morphological pillar detection\n');

    gray = rgb2gray(ref_image);
    gray_d = im2double(gray);
    [H, W] = size(gray);

    % Multi-scale top-hat and bottom-hat
    radii = P.MORPH_RADII;
    tophat_max = zeros(H, W);
    bothat_max = zeros(H, W);
    for r = radii
        se = strel('disk', r);
        tophat_max = max(tophat_max, imtophat(gray_d, se));
        bothat_max = max(bothat_max, imbothat(gray_d, se));
    end

    top_range = prctile(tophat_max(chip_interior), 99) - median(tophat_max(chip_interior));
    bot_range = prctile(bothat_max(chip_interior), 99) - median(bothat_max(chip_interior));

    if top_range >= bot_range
        feature_map = tophat_max;
        fprintf('  top-hat contrast=%.3f\n', top_range);
    else
        feature_map = bothat_max;
        fprintf('  bottom-hat contrast=%.3f\n', bot_range);
    end

    feature_vals = feature_map(chip_interior);
    max_feat = max(feature_vals);

    if max_feat < P.MORPH_CONTRAST_MIN
        fprintf('  Very low morphological contrast (%.4f)\n', max_feat);
        solid_mask = false(H, W);
    else
        feature_norm = feature_map / max_feat;
        th = graythresh(uint8(feature_norm(chip_interior) * 255));
        pillar_cand = (feature_norm > th) & chip_interior;

        pillar_cand = imopen(pillar_cand, strel('disk', 1));  % radius=1 to preserve small pillars
        pillar_cand = imclose(pillar_cand, strel('disk', 2));
        pillar_cand = bwareaopen(pillar_cand, P.MIN_BLOB_AREA_MORPH);
        pillar_cand = imfill(pillar_cand, 'holes');

        max_pillar_area = total_chip * P.MAX_PILLAR_AREA_FRAC;
        stats = regionprops(pillar_cand, 'Area', 'PixelIdxList');
        solid_mask = false(H, W);
        for k = 1:numel(stats)
            a = stats(k).Area;
            if a > P.MIN_BLOB_AREA_MORPH && a < max_pillar_area
                solid_mask(stats(k).PixelIdxList) = true;
            end
        end
    end

    % Otsu fallback if morphological found nothing
    pillar_fraction = sum(solid_mask(:)) / total_chip;
    if pillar_fraction < P.WARN_PILLAR_FRAC
        fprintf('  Morphological found few pillars (%.1f%%). Trying Otsu...\n', ...
            pillar_fraction * 100);

        chip_vals = gray_d(chip_interior);
        otsu_level = graythresh(uint8(chip_vals * 255)) * ...
            (max(chip_vals) - min(chip_vals)) + min(chip_vals);

        bright_mask = (gray_d > otsu_level) & chip_interior;
        dark_mask   = (gray_d <= otsu_level) & chip_interior;

        if sum(bright_mask(:)) < sum(dark_mask(:))
            pillar_raw = bright_mask;
        else
            pillar_raw = dark_mask;
        end

        pillar_raw = imopen(pillar_raw, strel('disk', 1));  % radius=1 to preserve small pillars
        pillar_raw = imclose(pillar_raw, strel('disk', 2));
        pillar_raw = bwareaopen(pillar_raw, P.MIN_BLOB_AREA_MORPH);
        pillar_raw = imfill(pillar_raw, 'holes');

        max_pillar_area = total_chip * P.MAX_PILLAR_AREA_FRAC;
        stats2 = regionprops(pillar_raw, 'Area', 'PixelIdxList');
        solid_mask2 = false(H, W);
        for k = 1:numel(stats2)
            a = stats2(k).Area;
            if a > P.MIN_BLOB_AREA_MORPH && a < max_pillar_area
                solid_mask2(stats2(k).PixelIdxList) = true;
            end
        end

        frac2 = sum(solid_mask2(:)) / total_chip;
        if frac2 > P.OTSU_MIN_FRAC && frac2 < P.OTSU_MAX_FRAC
            solid_mask = solid_mask2;
            fprintf('  Otsu result: %.1f%% pillars\n', frac2 * 100);
        else
            fprintf('  Otsu result %.1f%% not plausible\n', frac2 * 100);
        end
    end
end
