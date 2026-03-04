function [aligned, tform] = align_images(moving_image, fixed_image, config)
% ALIGN_IMAGES  Register moving RGB image to a fixed reference.
%
%   [aligned, tform] = align_images(moving_image, fixed_image, config)
%
%   Uses intensity-based registration to align frames in a time series.
%   The fixed image can be either an RGB image or a 2-D logical/grayscale mask.
%
%   Inputs:
%       moving_image - M1 x N1 x 3 uint8 RGB image to be aligned
%       fixed_image  - Reference image: RGB (M2xN2x3) or grayscale/logical (M2xN2)
%       config       - Pipeline configuration struct
%
%   Outputs:
%       aligned - Registered RGB image (same size as fixed_image)
%       tform   - affine2d / simtform2d geometric transformation object

    method = 'intensity';
    if isfield(config, 'registration') && isfield(config.registration, 'method')
        method = config.registration.method;
    end

    transform_type = 'similarity';
    if isfield(config, 'registration') && isfield(config.registration, 'transform')
        transform_type = config.registration.transform;
    end

    %% Prepare grayscale versions
    if size(moving_image, 3) == 3
        moving_gray = rgb2gray(moving_image);
    else
        moving_gray = moving_image;
    end

    if size(fixed_image, 3) == 3
        fixed_gray = rgb2gray(fixed_image);
    else
        fixed_gray = im2uint8(double(fixed_image));
    end

    %% Check if images are already the same size — skip if 'none'
    if strcmpi(method, 'none')
        aligned = imresize(moving_image, [size(fixed_gray,1), size(fixed_gray,2)]);
        tform = affine2d(eye(3));
        return;
    end

    %% Intensity-based registration
    [optimizer, metric] = imregconfig('multimodal');
    optimizer.InitialRadius = 1e-3;
    optimizer.MaximumIterations = 300;

    try
        tform = imregtform(im2double(moving_gray), im2double(fixed_gray), ...
            transform_type, optimizer, metric);
    catch ME
        warning('align_images:regFailed', ...
            'Registration failed (%s). Using identity transform.', ME.message);
        tform = affine2d(eye(3));
    end

    %% Apply transformation to RGB image
    output_view = imref2d(size(fixed_gray));
    if size(moving_image, 3) == 3
        aligned = imwarp(moving_image, tform, 'OutputView', output_view, ...
            'Interp', 'bilinear');
    else
        aligned = imwarp(moving_image, tform, 'OutputView', output_view);
    end

    fprintf('  Aligned image (method: %s, transform: %s)\n', method, transform_type);
end
