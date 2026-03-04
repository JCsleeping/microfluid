function fig = visualize_preprocessing(original, illumination_field, corrected, ...
    flow_domain, ref_image, config, solid_mask)
% VISUALIZE_PREPROCESSING  Display the preprocessing pipeline results.
%
%   fig = visualize_preprocessing(original, illumination_field, corrected,
%                                 flow_domain, ref_image, config)
%   fig = visualize_preprocessing(..., solid_mask)
%
%   The optional 7th argument solid_mask enables porosity cross-check.

    fig = figure('Name', 'Preprocessing Results', ...
        'Position', [50 50 1400 800], 'Color', 'w');

    % Guard: if critical inputs are empty, show placeholder and return
    if isempty(original) || isempty(flow_domain)
        text(0.5, 0.5, 'No preprocessing data available', ...
            'HorizontalAlignment', 'center', 'FontSize', 16, 'Units', 'normalized');
        axis off;
        return;
    end

    if nargin < 7, solid_mask = []; end

    %% Subplot 1: Original RGB
    subplot(2,3,1);
    imshow(original);
    title('Original RGB Image', 'FontSize', 12);

    %% Subplot 2: Illumination Field
    subplot(2,3,2);
    imagesc(illumination_field);
    colormap(gca, 'hot'); colorbar;
    title('Estimated Illumination Field', 'FontSize', 12);
    axis image off;

    %% Subplot 3: Illumination Corrected
    subplot(2,3,3);
    imshow(corrected);
    title('Illumination Corrected', 'FontSize', 12);

    %% Subplot 4: Flow Domain Mask — with porosity info
    subplot(2,3,4);
    imshow(flow_domain);

    % Calculate porosity from flow_domain and solid_mask
    pore_px = sum(flow_domain(:));

    % Cross-check with solid_mask if available
    if ~isempty(solid_mask) && isequal(size(solid_mask), size(flow_domain))
        pillar_px = sum(solid_mask(:));
        % chip_interior = pore + pillar (exclude background outside chip)
        chip_px = pore_px + pillar_px;
        porosity_fd = pore_px / max(chip_px, 1) * 100;
        porosity_sm = (1 - pillar_px / max(chip_px, 1)) * 100;

        % Both should be identical since flow_domain = chip & ~solid
        if abs(porosity_fd - porosity_sm) < 0.5
            title(sprintf('Flow Domain (porosity=%.1f%% OK)', porosity_fd), ...
                'FontSize', 11, 'Color', [0 0.5 0]);
        else
            title(sprintf('Flow Domain %.1f%% vs Pillars %.1f%% MISMATCH', ...
                porosity_fd, porosity_sm), 'FontSize', 11, 'Color', 'r');
        end
    else
        % Without solid_mask, estimate chip area as non-zero region
        total_px = numel(flow_domain);
        porosity_fd = pore_px / total_px * 100;
        title(sprintf('Flow Domain Mask (porosity~%.1f%%)', porosity_fd), 'FontSize', 11);
    end

    %% Subplot 5: Reference Image (aligned)
    subplot(2,3,5);
    imshow(ref_image);
    title('Reference Image (aligned)', 'FontSize', 12);

    %% Subplot 6: Alignment Verification — QUANTITATIVE
    subplot(2,3,6);

    % Resize for comparison if dimensions differ
    [H_fd, W_fd] = size(flow_domain);
    ref_for_cmp = ref_image;
    corr_for_cmp = corrected;
    if size(ref_for_cmp,1) ~= H_fd || size(ref_for_cmp,2) ~= W_fd
        ref_for_cmp = imresize(ref_for_cmp, [H_fd W_fd]);
    end
    if size(corr_for_cmp,1) ~= H_fd || size(corr_for_cmp,2) ~= W_fd
        corr_for_cmp = imresize(corr_for_cmp, [H_fd W_fd]);
    end

    gray_ref  = im2double(rgb2gray(ref_for_cmp));
    gray_corr = im2double(rgb2gray(corr_for_cmp));

    % --- Metric 1: SSIM ---
    try
        ssim_val = ssim(gray_ref, gray_corr);
    catch
        ssim_val = NaN;
    end

    % --- Metric 2: Normalized Cross-Correlation ---
    ncc_val = corr2(gray_ref, gray_corr);

    % --- Metric 3: Pixel shift estimation (via cross-correlation peak) ---
    try
        cc = normxcorr2(gray_ref(50:end-50, 50:end-50), gray_corr);
        [~, max_idx] = max(cc(:));
        [yp, xp] = ind2sub(size(cc), max_idx);
        % Expected peak position for perfect alignment
        [h_t, w_t] = size(gray_ref(50:end-50, 50:end-50));
        dy = yp - h_t;
        dx = xp - w_t;
    catch
        dx = NaN; dy = NaN;
    end

    % Draw the overlay image (same as before)
    boundary = bwperim(flow_domain);
    overlay = ref_for_cmp;
    if size(overlay,3) == 3 && size(overlay,1) == size(boundary,1) && size(overlay,2) == size(boundary,2)
        for c = 1:3
            ch = overlay(:,:,c);
            if c == 2  % green
                ch(boundary) = 255;
            else
                ch(boundary) = 0;
            end
            overlay(:,:,c) = ch;
        end
    end
    imshow(overlay);

    % Annotate with quantitative metrics
    metrics_str = sprintf('SSIM = %.4f\nNCC  = %.4f\nShift = (%+d, %+d) px', ...
        ssim_val, ncc_val, dx, dy);

    % Color code: green if good, yellow if marginal, red if bad
    if ssim_val > 0.90
        txt_color = [0 0.6 0];
        quality = 'GOOD';
    elseif ssim_val > 0.75
        txt_color = [0.8 0.6 0];
        quality = 'FAIR';
    else
        txt_color = [0.8 0 0];
        quality = 'POOR';
    end

    title(sprintf('Alignment: %s', quality), 'FontSize', 12, 'Color', txt_color);

    % Place text box with metrics
    text(10, 30, metrics_str, ...
        'FontSize', 10, 'FontWeight', 'bold', 'Color', txt_color, ...
        'BackgroundColor', [1 1 1 0.8], 'EdgeColor', txt_color, ...
        'Margin', 4, 'VerticalAlignment', 'top');

    sgtitle('Preprocessing Pipeline', 'FontSize', 14, 'FontWeight', 'bold');

    if config.visualization.save_figures
        save_subplots(fig, config.output_path, 1, config.visualization.figure_format);
    end
end
