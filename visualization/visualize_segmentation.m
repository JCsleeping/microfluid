function fig = visualize_segmentation(ref_image, color_channel, dnapl_mask, ...
    flow_domain, confidence_map, config)
% VISUALIZE_SEGMENTATION  Display DNAPL segmentation results.
%
%   fig = visualize_segmentation(ref_image, color_channel, dnapl_mask,
%                                flow_domain, confidence_map, config)

    fig = figure('Name', 'Segmentation Results', ...
        'Position', [50 50 1400 600], 'Color', 'w');

    % Guard: if critical inputs are empty, show placeholder and return
    if isempty(ref_image) || isempty(dnapl_mask) || isempty(flow_domain)
        text(0.5, 0.5, 'No segmentation data available', ...
            'HorizontalAlignment', 'center', 'FontSize', 16, 'Units', 'normalized');
        axis off;
        return;
    end

    % Panel 1: Reference image
    subplot(2,3,1);
    imshow(ref_image);
    title('Reference Image', 'FontSize', 11);

    % Panel 2: Color channel used for segmentation (Lab a*)
    % Mask out solid regions to show only pixels that participated in segmentation
    subplot(2,3,2);
    a_display = color_channel;
    a_display(~flow_domain) = NaN;  % NaN renders as background color
    h_a = imagesc(a_display);
    set(h_a, 'AlphaData', double(flow_domain));
    set(gca, 'Color', [0.7 0.7 0.7]);  % gray background for solid
    colormap(gca, 'jet'); colorbar;
    title('Lab a* Channel (pore only)', 'FontSize', 11);
    axis image off;

    % Panel 3: Confidence / probability map (pore only)
    subplot(2,3,3);
    conf_display = confidence_map;
    conf_display(~flow_domain) = NaN;
    h_c = imagesc(conf_display, [0 1]);
    set(h_c, 'AlphaData', double(flow_domain));
    set(gca, 'Color', [0.7 0.7 0.7]);
    colormap(gca, 'parula'); colorbar;
    title('DNAPL Probability Map (pore only)', 'FontSize', 11);
    axis image off;

    % Panel 4: Binary DNAPL mask
    subplot(2,3,4);
    imshow(dnapl_mask);
    title('Binary DNAPL Mask', 'FontSize', 11);

    % Panel 5: Three-phase map (solid=gray, water=blue, DNAPL=red)
    subplot(2,3,5);
    three_phase = zeros([size(flow_domain), 3], 'uint8');
    % Solid = gray
    solid = ~flow_domain;
    three_phase(:,:,1) = uint8(solid) * 128;
    three_phase(:,:,2) = uint8(solid) * 128;
    three_phase(:,:,3) = uint8(solid) * 128;
    % Water = blue
    water = flow_domain & ~dnapl_mask;
    three_phase(:,:,3) = three_phase(:,:,3) + uint8(water) * 200;
    three_phase(:,:,1) = three_phase(:,:,1) + uint8(water) * 50;
    three_phase(:,:,2) = three_phase(:,:,2) + uint8(water) * 100;
    % DNAPL = red
    three_phase(:,:,1) = three_phase(:,:,1) + uint8(dnapl_mask) * 220;
    three_phase(:,:,2) = three_phase(:,:,2) + uint8(dnapl_mask) * 40;
    three_phase(:,:,3) = three_phase(:,:,3) + uint8(dnapl_mask) * 40;
    imshow(three_phase);
    title('Three-Phase Distribution', 'FontSize', 11);

    % Panel 6: DNAPL overlay on reference image
    subplot(2,3,6);
    if size(ref_image, 3) == 3
        % Tint DNAPL region red on the reference image
        overlay = ref_image;
        mask3 = repmat(dnapl_mask, [1 1 3]);
        red_tint = zeros(size(ref_image), 'uint8');
        red_tint(:,:,1) = 255;
        overlay(mask3) = uint8(0.5*double(ref_image(mask3)) + ...
            0.5*double(red_tint(mask3)));
        imshow(overlay);
    else
        imshow(dnapl_mask);
    end
    title('DNAPL Overlay', 'FontSize', 11);

    Sn = sum(dnapl_mask(:)) / max(sum(flow_domain(:)),1);
    sgtitle(sprintf('DNAPL Segmentation  (S_n = %.3f)', Sn), ...
        'FontSize', 14, 'FontWeight', 'bold');

    if config.visualization.save_figures
        save_subplots(fig, config.output_path, 2, config.visualization.figure_format);
    end
end
