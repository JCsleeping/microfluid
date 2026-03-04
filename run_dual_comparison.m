%% RUN_DUAL_COMPARISON  Run GMM and Otsu segmentation on the same data and compare.
%
%   This wrapper script calls main_DNAPL_pipeline TWICE on the same dataset:
%     Run 1: segmentation.method = 'gmm'
%     Run 2: segmentation.method = 'otsu'
%
%   Results are saved to separate output folders and a comparison figure
%   is generated automatically.
%
%   USAGE:
%     1. Configure your experiment parameters below (same as config_pipeline)
%     2. Run this script:  >> run_dual_comparison
%
%   NOTE: No existing code is modified. This script only calls existing functions.

%% ====================================================================
%  USER SETTINGS — 和 config_pipeline.m 一样，在这里设置你的参数
%  ====================================================================
%  如果不需要修改，保持为空 {}，将使用 config_pipeline.m 中的默认值。

% user_overrides 必须是 1×N 的行向量，否则 {:} 展开顺序会错
% 推荐：指定页面子集以节省内存和时间
%   e.g. 'pages', [1, 20, 40, 60, 80, 100, 120, 140], ...
% 推荐：关闭交互弹窗（如果你已经知道参数）
%   e.g. 'preprocess.manual_crop_rect', [x, y, w, h], ...
%   e.g. 'illumination.kernel_size', 50, ...
%   e.g. 'flow_domain_crop_rect', [x, y, w, h], ...
user_overrides = { ...
    'visualization.show_figures', false, ...
    'visualization.save_figures', true  ...
};

%% ====================================================================
%  DO NOT MODIFY BELOW — 以下代码自动运行
%  ====================================================================

fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║        DNAPL Segmentation: GMM vs Otsu Comparison        ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n\n');

total_timer = tic;

%% Step 1: Create base config
config_base = config_pipeline(user_overrides{:});

% Create a shared timestamp for output folders
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
base_output = fileparts(config_base.output_path);

%% ====================================================================
%  RUN 1: GMM Method
%  ====================================================================
fprintf('\n');
fprintf('┌────────────────────────────────────────────────────────────┐\n');
fprintf('│  RUN 1 / 2 : GMM Method                                  │\n');
fprintf('└────────────────────────────────────────────────────────────┘\n');

config_gmm = config_base;
config_gmm.segmentation.method = 'gmm';
config_gmm.output_path = fullfile(base_output, ['compare_GMM_' timestamp]);

results_gmm = main_DNAPL_pipeline(config_gmm);

% Capture resolved parameters to avoid interactive prompts in Run 2
resolved_params = struct();
if isfield(config_gmm.preprocess, 'saved_crop_rect')
    resolved_params.crop_rect = config_gmm.preprocess.saved_crop_rect;
end
if isfield(config_gmm.preprocess, 'roi_vertices')
    resolved_params.roi_vertices = config_gmm.preprocess.roi_vertices;
end
if isnumeric(config_gmm.illumination.kernel_size)
    resolved_params.kernel_size = config_gmm.illumination.kernel_size;
end
if isfield(config_gmm, 'flow_domain_crop_rect') && ~isempty(config_gmm.flow_domain_crop_rect)
    resolved_params.flow_domain_crop_rect = config_gmm.flow_domain_crop_rect;
end

fprintf('\n  GMM run complete. Saved to: %s\n', config_gmm.output_path);

%% ====================================================================
%  RUN 2: Otsu Method (reuse interactive parameters from Run 1)
%  ====================================================================
fprintf('\n');
fprintf('┌────────────────────────────────────────────────────────────┐\n');
fprintf('│  RUN 2 / 2 : Otsu Method                                 │\n');
fprintf('└────────────────────────────────────────────────────────────┘\n');

config_otsu = config_base;
config_otsu.segmentation.method = 'otsu';
config_otsu.output_path = fullfile(base_output, ['compare_Otsu_' timestamp]);

% Inject resolved parameters (skip interactive prompts)
if isfield(resolved_params, 'crop_rect')
    config_otsu.preprocess.manual_crop_rect = resolved_params.crop_rect;
    config_otsu.preprocess.saved_crop_rect  = resolved_params.crop_rect;
end
if isfield(resolved_params, 'roi_vertices')
    config_otsu.preprocess.roi_vertices = resolved_params.roi_vertices;
end
if isfield(resolved_params, 'kernel_size')
    config_otsu.illumination.kernel_size = resolved_params.kernel_size;
end
if isfield(resolved_params, 'flow_domain_crop_rect')
    config_otsu.flow_domain_crop_rect = resolved_params.flow_domain_crop_rect;
end

results_otsu = main_DNAPL_pipeline(config_otsu);

fprintf('\n  Otsu run complete. Saved to: %s\n', config_otsu.output_path);

%% ====================================================================
%  COMPARISON: Generate side-by-side figures
%  ====================================================================
fprintf('\n');
fprintf('┌────────────────────────────────────────────────────────────┐\n');
fprintf('│  COMPARISON: Generating figures                           │\n');
fprintf('└────────────────────────────────────────────────────────────┘\n');

compare_output = fullfile(base_output, ['compare_REPORT_' timestamp]);
if ~isfolder(compare_output), mkdir(compare_output); end

% --- Ensure masks are same size (interactive crop may differ slightly) ---
sz_gmm  = size(results_gmm.dnapl_mask);
sz_otsu = size(results_otsu.dnapl_mask);
if ~isequal(sz_gmm, sz_otsu)
    fprintf('  NOTE: Mask sizes differ (GMM %dx%d vs Otsu %dx%d). Resizing Otsu to match.\n', ...
        sz_gmm(1), sz_gmm(2), sz_otsu(1), sz_otsu(2));
    results_otsu.dnapl_mask = imresize(results_otsu.dnapl_mask, sz_gmm, 'nearest') > 0;
    results_otsu.ref_image  = imresize(results_otsu.ref_image, sz_gmm(1:2));
    if isfield(results_otsu, 'flow_domain')
        results_otsu.flow_domain = imresize(results_otsu.flow_domain, sz_gmm, 'nearest') > 0;
    end
end

% --- Figure 1: Single-frame mask comparison ---
fig1 = figure('Name', 'Segmentation Comparison', ...
    'Position', [50 50 1400 900], 'Color', 'w');

% Reference image
subplot(2, 3, 1);
imshow(results_gmm.ref_image);
title('Reference Image', 'FontSize', 12);

% GMM mask
subplot(2, 3, 2);
imshow(results_gmm.dnapl_mask);
title(sprintf('GMM  (Sn = %.4f)', results_gmm.saturation.Sn), 'FontSize', 12);

% Otsu mask
subplot(2, 3, 3);
imshow(results_otsu.dnapl_mask);
title(sprintf('Otsu (Sn = %.4f)', results_otsu.saturation.Sn), 'FontSize', 12);

% GMM overlay
subplot(2, 3, 4);
overlay_gmm = im2double(results_gmm.ref_image);
overlay_gmm(:,:,1) = overlay_gmm(:,:,1) + 0.4 * double(results_gmm.dnapl_mask);
overlay_gmm = min(overlay_gmm, 1);
imshow(overlay_gmm);
title('GMM Overlay', 'FontSize', 12);

% Otsu overlay
subplot(2, 3, 5);
overlay_otsu = im2double(results_otsu.ref_image);
overlay_otsu(:,:,1) = overlay_otsu(:,:,1) + 0.4 * double(results_otsu.dnapl_mask);
overlay_otsu = min(overlay_otsu, 1);
imshow(overlay_otsu);
title('Otsu Overlay', 'FontSize', 12);

% Difference map
subplot(2, 3, 6);
diff_mask = zeros(size(results_gmm.dnapl_mask, 1), size(results_gmm.dnapl_mask, 2), 3);
only_gmm  = results_gmm.dnapl_mask & ~results_otsu.dnapl_mask;
only_otsu = results_otsu.dnapl_mask & ~results_gmm.dnapl_mask;
both      = results_gmm.dnapl_mask &  results_otsu.dnapl_mask;
diff_mask(:,:,1) = double(only_gmm);    % Red   = GMM only
diff_mask(:,:,2) = double(both);         % Green = Both agree
diff_mask(:,:,3) = double(only_otsu);    % Blue  = Otsu only
imshow(diff_mask);
title('Difference (R=GMM only, G=Both, B=Otsu only)', 'FontSize', 11);

sgtitle('Frame 1: GMM vs Otsu Segmentation', 'FontSize', 14, 'FontWeight', 'bold');
saveas(fig1, fullfile(compare_output, 'comparison_masks.png'));

% --- Figure 2: Blob geometry comparison ---
fig2 = figure('Name', 'Blob Comparison', ...
    'Position', [100 100 1000 400], 'Color', 'w');

subplot(1, 3, 1);
bar([results_gmm.blobs.num_blobs, results_otsu.blobs.num_blobs]);
set(gca, 'XTickLabel', {'GMM', 'Otsu'}, 'FontSize', 12);
ylabel('Blob Count');
title('Number of Blobs', 'FontSize', 12);

subplot(1, 3, 2);
bar([results_gmm.saturation.Sn, results_otsu.saturation.Sn]);
set(gca, 'XTickLabel', {'GMM', 'Otsu'}, 'FontSize', 12);
ylabel('Sn');
title('DNAPL Saturation', 'FontSize', 12);

subplot(1, 3, 3);
bar([results_gmm.interfaces.dnapl_water_length_px, ...
     results_otsu.interfaces.dnapl_water_length_px]);
set(gca, 'XTickLabel', {'GMM', 'Otsu'}, 'FontSize', 12);
ylabel('Length [px]');
title('DNAPL-Water Interface', 'FontSize', 12);

sgtitle('Single-Frame Metrics: GMM vs Otsu', 'FontSize', 14, 'FontWeight', 'bold');
saveas(fig2, fullfile(compare_output, 'comparison_metrics.png'));

% --- Figure 3: Time series comparison (if multi-frame) ---
has_timeseries = isfield(results_gmm, 'solubilization') && ...
                 isfield(results_otsu, 'solubilization');

if has_timeseries
    tv = results_gmm.time_vector;
    sol_gmm  = results_gmm.solubilization;
    sol_otsu = results_otsu.solubilization;

    fig3 = figure('Name', 'Time Series Comparison', ...
        'Position', [100 50 1200 800], 'Color', 'w');

    % Sn(t)
    subplot(2, 2, 1);
    plot(tv, sol_gmm.saturation_vs_time, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold on;
    plot(tv, sol_otsu.saturation_vs_time, 'r-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    xlabel('Time'); ylabel('S_n');
    title('DNAPL Saturation vs Time', 'FontSize', 12);
    legend('GMM', 'Otsu', 'Location', 'best');
    grid on;

    % Blob count
    subplot(2, 2, 2);
    plot(tv, sol_gmm.num_blobs_vs_time, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold on;
    plot(tv, sol_otsu.num_blobs_vs_time, 'r-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    xlabel('Time'); ylabel('Blob Count');
    title('Number of Blobs vs Time', 'FontSize', 12);
    legend('GMM', 'Otsu', 'Location', 'best');
    grid on;

    % Mean blob size
    subplot(2, 2, 3);
    plot(tv, sol_gmm.mean_blob_size_vs_time, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold on;
    plot(tv, sol_otsu.mean_blob_size_vs_time, 'r-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    xlabel('Time'); ylabel('Mean Area [px]');
    title('Mean Blob Size vs Time', 'FontSize', 12);
    legend('GMM', 'Otsu', 'Location', 'best');
    grid on;

    % Interface length
    subplot(2, 2, 4);
    plot(tv, sol_gmm.interface_area_vs_time, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold on;
    plot(tv, sol_otsu.interface_area_vs_time, 'r-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    xlabel('Time'); ylabel('Interface Length [px]');
    title('DNAPL-Water Interface vs Time', 'FontSize', 12);
    legend('GMM', 'Otsu', 'Location', 'best');
    grid on;

    sgtitle('Time Series: GMM (blue) vs Otsu (red)', 'FontSize', 14, 'FontWeight', 'bold');
    saveas(fig3, fullfile(compare_output, 'comparison_timeseries.png'));
end

%% ====================================================================
%  SUMMARY REPORT
%  ====================================================================
fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║                   COMPARISON SUMMARY                     ║\n');
fprintf('╠════════════════════════════════════════════════════════════╣\n');
fprintf('║  Metric               │  GMM          │  Otsu           ║\n');
fprintf('╠────────────────────────┼───────────────┼─────────────────╣\n');
fprintf('║  Sn (frame 1)         │  %.6f     │  %.6f       ║\n', ...
    results_gmm.saturation.Sn, results_otsu.saturation.Sn);
fprintf('║  Blob count           │  %5d         │  %5d           ║\n', ...
    results_gmm.blobs.num_blobs, results_otsu.blobs.num_blobs);
fprintf('║  DNAPL-water iface    │  %8.0f px  │  %8.0f px    ║\n', ...
    results_gmm.interfaces.dnapl_water_length_px, ...
    results_otsu.interfaces.dnapl_water_length_px);
fprintf('║  Mass transfer rate   │  %.2e   │  %.2e     ║\n', ...
    results_gmm.mass_transfer.mass_transfer_rate, ...
    results_otsu.mass_transfer.mass_transfer_rate);

% Pixel agreement
agreement = sum(results_gmm.dnapl_mask(:) == results_otsu.dnapl_mask(:)) / ...
            numel(results_gmm.dnapl_mask) * 100;
fprintf('║  Pixel agreement      │       %.2f%%                    ║\n', agreement);

fprintf('╠════════════════════════════════════════════════════════════╣\n');

if has_timeseries
    sn_diff = abs(sol_gmm.saturation_vs_time - sol_otsu.saturation_vs_time);
    fprintf('║  Mean |ΔSn| over time │  %.6f                       ║\n', mean(sn_diff));
    fprintf('║  Max  |ΔSn| over time │  %.6f                       ║\n', max(sn_diff));
end

total_time = toc(total_timer);
fprintf('╠════════════════════════════════════════════════════════════╣\n');
fprintf('║  Total time: %.1f seconds                                ║\n', total_time);
fprintf('╠════════════════════════════════════════════════════════════╣\n');
fprintf('║  GMM results:  %s\n', config_gmm.output_path);
fprintf('║  Otsu results: %s\n', config_otsu.output_path);
fprintf('║  Comparison:   %s\n', compare_output);
fprintf('╚════════════════════════════════════════════════════════════╝\n');

% Save comparison data
comparison.results_gmm  = results_gmm;
comparison.results_otsu = results_otsu;
comparison.agreement_pct = agreement;
comparison.config_gmm   = config_gmm;
comparison.config_otsu  = config_otsu;
if has_timeseries
    comparison.sn_diff_mean = mean(sn_diff);
    comparison.sn_diff_max  = max(sn_diff);
end
save(fullfile(compare_output, 'comparison_results.mat'), 'comparison', '-v7.3');
fprintf('\n  Comparison data saved to: comparison_results.mat\n');
