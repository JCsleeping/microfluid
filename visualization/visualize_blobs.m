function fig = visualize_blobs(blob_results, config)
% VISUALIZE_BLOBS  Display blob geometric analysis results.
%
%   fig = visualize_blobs(blob_results, config)

    fig = figure('Name', 'Blob Geometry Analysis', ...
        'Position', [50 50 1600 800], 'Color', 'w');

    labeled = blob_results.labeled_image;
    props   = blob_results.props;
    nb      = blob_results.num_blobs;

    if nb == 0
        text(0.5, 0.5, 'No DNAPL blobs detected', ...
            'HorizontalAlignment', 'center', 'FontSize', 16);
        return;
    end

    areas        = [props.Area];
    circularities = [props.Circularity];

    % Panel 1: Color-coded labeled blobs
    subplot(2,3,1);
    rgb_label = label2rgb(labeled, config.visualization.colormap_blobs, 'k', 'shuffle');
    imshow(rgb_label);
    title(sprintf('Labeled Blobs (N = %d)', nb), 'FontSize', 11);

    % Panel 2: Blobs colored by area
    subplot(2,3,2);
    area_map = zeros(size(labeled));
    for i = 1:nb
        area_map(labeled == i) = areas(i);
    end
    imagesc(area_map);
    colormap(gca, 'hot'); colorbar;
    title('Blobs Colored by Area', 'FontSize', 11);
    axis image off;

    % Panel 3: Size distribution histogram
    subplot(2,3,3);
    if max(areas) / max(min(areas),1) > 100
        histogram(log10(areas), 30, 'FaceColor', [0.2 0.6 0.8]);
        xlabel('log_{10}(Blob Area) [pixels]');
    else
        histogram(areas, 30, 'FaceColor', [0.2 0.6 0.8]);
        xlabel('Blob Area [pixels]');
    end
    ylabel('Count');
    title('Size Distribution', 'FontSize', 11);
    grid on;

    % Panel 4: Circularity distribution
    subplot(2,3,4);
    histogram(circularities, 20, 'FaceColor', [0.8 0.4 0.2]);
    xlabel('Circularity');
    ylabel('Count');
    title('Circularity Distribution', 'FontSize', 11);
    xlim([0 1.2]);
    grid on;

    % Panel 5: Area vs Circularity scatter
    subplot(2,3,5);
    scatter(areas, circularities, 25, 'filled', 'MarkerFaceAlpha', 0.6);
    xlabel('Area [pixels]');
    ylabel('Circularity');
    title('Area vs Circularity', 'FontSize', 11);
    if max(areas) / max(min(areas),1) > 100
        set(gca, 'XScale', 'log');
    end
    grid on;

    % Panel 6: Summary statistics text
    subplot(2,3,6);
    axis off;
    stats_text = {
        sprintf('Number of blobs:    %d', nb)
        sprintf('Total DNAPL area:   %.0f px', sum(areas))
        sprintf('Mean blob area:     %.1f px', mean(areas))
        sprintf('Median blob area:   %.1f px', median(areas))
        sprintf('Largest blob:       %.0f px', max(areas))
        sprintf('Smallest blob:      %.0f px', min(areas))
        ''
        sprintf('Mean circularity:   %.3f', mean(circularities))
        sprintf('Median circularity: %.3f', median(circularities))
        ''
        sprintf('Ganglia types:')
        sprintf('  Singlets (<50 px):   %d', sum(areas < 50))
        sprintf('  Ganglia (50-500 px): %d', sum(areas >= 50 & areas < 500))
        sprintf('  Pools (>500 px):     %d', sum(areas >= 500))
    };
    text(0.05, 0.95, stats_text, 'VerticalAlignment', 'top', ...
        'FontSize', 10, 'FontName', 'FixedWidth');
    title('Summary Statistics', 'FontSize', 11);

    sgtitle('DNAPL Blob Geometry Analysis', 'FontSize', 14, 'FontWeight', 'bold');

    if config.visualization.save_figures
        save_subplots(fig, config.output_path, 3, config.visualization.figure_format);
    end
end
