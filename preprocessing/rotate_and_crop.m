function [rotated, angle_deg, crop_rect] = rotate_and_crop(rgb_image, config)
% ROTATE_AND_CROP  Detect chip orientation, rotate to axis-aligned, and crop.
%
%   [rotated, angle_deg, crop_rect] = rotate_and_crop(rgb_image, config)
%
%   The microfluidic chip appears rotated ~45 degrees against a gray
%   background. This function detects the chip region, computes its
%   orientation, rotates the image so the chip is axis-aligned, and crops
%   to the chip bounding box.
%
%   Inputs:
%       rgb_image - M x N x 3 uint8 RGB image
%       config    - pipeline configuration struct
%
%   Outputs:
%       rotated   - Axis-aligned, cropped RGB image
%       angle_deg - Detected rotation angle (degrees)
%       crop_rect - [x, y, width, height] of the crop rectangle

    %% Check for manual override
    if ~isempty(config.preprocess.rotation_angle)
        angle_deg = config.preprocess.rotation_angle;
    else
        angle_deg = detect_chip_angle(rgb_image);
    end

    %% Rotate the image (skip if angle is 0)
    if angle_deg == 0
        rotated_full = rgb_image;
    else
        rotated_full = imrotate(rgb_image, angle_deg, 'bilinear', 'loose');
    end

    %% Priority 1: manual_crop_rect from config (user-specified ROI)
    if isfield(config.preprocess, 'manual_crop_rect') && ...
            ~isempty(config.preprocess.manual_crop_rect) && ...
            isnumeric(config.preprocess.manual_crop_rect)
        crop_rect = config.preprocess.manual_crop_rect;
        crop_rect = clip_crop_rect(crop_rect, rotated_full);
        rotated = imcrop(rotated_full, crop_rect);
        fprintf('  Rotation: %.1f deg | Crop [%d x %d] (manual ROI)\n', ...
            angle_deg, size(rotated, 2), size(rotated, 1));
        return;
    end

    %% Priority 2: saved_crop_rect (reuse reference frame's crop)
    if isfield(config.preprocess, 'saved_crop_rect') && ~isempty(config.preprocess.saved_crop_rect)
        crop_rect = config.preprocess.saved_crop_rect;
        crop_rect = clip_crop_rect(crop_rect, rotated_full);
        rotated = imcrop(rotated_full, crop_rect);
        fprintf('  Rotation: %.1f deg | Crop [%d x %d] (reusing reference)\n', ...
            angle_deg, size(rotated, 2), size(rotated, 1));
        return;
    end

    %% Priority 3: auto-detect chip region
    gray = rgb2gray(rotated_full);

    % The chip is brighter (white/pink) than the gray background
    % Use Otsu to separate chip from background
    level = graythresh(gray);
    chip_mask = imbinarize(gray, level * 0.9);  % slightly lower threshold to be inclusive

    % Clean up: remove small noise, fill holes
    chip_mask = bwareaopen(chip_mask, round(numel(chip_mask) * 0.001));
    chip_mask = imclose(chip_mask, strel('disk', 10));
    chip_mask = imfill(chip_mask, 'holes');

    % Find bounding box of largest connected component
    stats = regionprops(chip_mask, 'BoundingBox', 'Area');
    if isempty(stats)
        warning('rotate_and_crop:noChip', 'Could not detect chip region. Returning rotated image without cropping.');
        rotated = rotated_full;
        crop_rect = [1, 1, size(rotated_full, 2), size(rotated_full, 1)];
        return;
    end

    [~, idx] = max([stats.Area]);
    bb = stats(idx).BoundingBox;

    % Add a small margin (2% of image size)
    margin = round(0.02 * max(size(gray)));
    x1 = max(1, round(bb(1) - margin));
    y1 = max(1, round(bb(2) - margin));
    x2 = min(size(rotated_full, 2), round(bb(1) + bb(3) + margin));
    y2 = min(size(rotated_full, 1), round(bb(2) + bb(4) + margin));

    crop_rect = [x1, y1, x2 - x1, y2 - y1];
    rotated = imcrop(rotated_full, crop_rect);

    fprintf('  Rotation angle: %.1f deg | Cropped to [%d x %d]\n', ...
        angle_deg, size(rotated, 2), size(rotated, 1));
end


function angle_deg = detect_chip_angle(rgb_image)
% DETECT_CHIP_ANGLE  Detect the rotation angle of a rectangular chip.
%
%   Uses PCA on the chip boundary to find the principal axis, then
%   computes the rotation needed to align edges horizontally/vertically.

    gray = rgb2gray(rgb_image);
    level = graythresh(gray);
    bw = imbinarize(gray, level * 0.9);

    bw = bwareaopen(bw, round(numel(bw) * 0.001));
    bw = imclose(bw, strel('disk', 10));
    bw = imfill(bw, 'holes');

    % Check that a region was detected
    if ~any(bw(:))
        angle_deg = 0;
        warning('detect_chip_angle:noRegion', 'Could not detect chip. Using 0 degrees.');
        return;
    end

    % Use PCA on boundary points for robust angle estimation
    boundaries = bwboundaries(bw);
    if isempty(boundaries)
        angle_deg = 0;
        warning('detect_chip_angle:noBoundary', 'No boundary found. Using 0 degrees.');
        return;
    end

    % Use the longest boundary (likely the chip outline)
    lengths = cellfun(@(b) size(b,1), boundaries);
    [~, best] = max(lengths);
    B = boundaries{best};

    % PCA: find principal axis direction
    coords = [B(:,2), B(:,1)];  % [x, y]
    coords_centered = coords - mean(coords);
    [~, ~, V] = svd(coords_centered, 'econ');
    pca_angle = atan2d(V(2,1), V(1,1));

    % We want chip edges axis-aligned. The PCA angle gives the major axis.
    % For a rectangular chip, snap to the nearest multiple of 90 degrees.
    % The correction angle is the remainder after dividing by 90.
    remainder = mod(pca_angle, 90);
    if remainder > 45
        remainder = remainder - 90;
    end
    angle_deg = -remainder;
end


function rect = clip_crop_rect(rect, img)
% CLIP_CROP_RECT  Clip [x,y,w,h] to image bounds.
    [H, W, ~] = size(img);
    x1 = max(1, rect(1));
    y1 = max(1, rect(2));
    x2 = min(W, rect(1) + rect(3));
    y2 = min(H, rect(2) + rect(4));
    rect = [x1, y1, x2 - x1, y2 - y1];
end
