function kernel_size = select_illumination_kernel(rgb_image)
% SELECT_ILLUMINATION_KERNEL  Interactive comparison of illumination
% correction with different kernel sizes.
%
%   kernel_size = select_illumination_kernel(rgb_image)
%
%   Displays a 2x5 grid showing the image corrected with 10 different
%   morphological kernel sizes (10, 20, ..., 100). User picks the best one.
%
%   Input:
%       rgb_image   - M x N x 3 uint8 RGB image (cropped, pre-correction)
%
%   Output:
%       kernel_size - Selected kernel radius (integer)

    kernels = 10:10:100;

    fprintf('  Computing illumination correction for %d kernel sizes...\n', numel(kernels));

    fig = figure('Name', 'Select Illumination Kernel Size', ...
        'Position', [30 30 1700 850], 'Color', 'w');

    for i = 1:numel(kernels)
        subplot(2, 5, i);
        params = struct('kernel_size', kernels(i));
        [corrected, ~] = correct_illumination(rgb_image, 'morphological', params);
        imshow(corrected);
        title(sprintf('Kernel = %d', kernels(i)), 'FontSize', 12, 'FontWeight', 'bold');
    end

    sgtitle({'Illumination Correction: Select the best kernel size', ...
        'Smaller kernel = more local correction | Larger kernel = smoother background'}, ...
        'FontSize', 14, 'FontWeight', 'bold');

    % Ask user to pick
    answer = inputdlg( ...
        sprintf('Enter kernel size (%d to %d, or any value):', kernels(1), kernels(end)), ...
        'Kernel Size Selection', [1 40], {'50'});

    if isempty(answer)
        kernel_size = 50;
        fprintf('  No selection made. Using default kernel = 50\n');
    else
        kernel_size = round(str2double(answer{1}));
        if isnan(kernel_size) || kernel_size < 1
            kernel_size = 50;
            fprintf('  Invalid input. Using default kernel = 50\n');
        else
            fprintf('  Selected kernel size = %d\n', kernel_size);
        end
    end

    close(fig);
end
