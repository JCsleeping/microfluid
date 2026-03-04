function mask_clean = refine_mask(mask, morph_radius, min_blob_area)
% REFINE_MASK  Morphological cleanup of a binary segmentation mask.
%
%   mask_clean = refine_mask(mask, morph_radius, min_blob_area)
%
%   Applies opening (remove noise), closing (fill small gaps), and
%   area filtering (remove tiny blobs).
%
%   Inputs:
%       mask           - M x N logical binary mask
%       morph_radius   - Disk SE radius for open/close (default 2)
%       min_blob_area  - Minimum connected-component area in pixels (default 10)
%
%   Output:
%       mask_clean - Cleaned binary mask

    if nargin < 2 || isempty(morph_radius),  morph_radius  = 2;  end
    if nargin < 3 || isempty(min_blob_area), min_blob_area = 10; end

    se = strel('disk', morph_radius);

    mask_clean = imopen(mask, se);       % remove small protrusions / noise
    mask_clean = imclose(mask_clean, se); % fill small gaps
    mask_clean = bwareaopen(mask_clean, min_blob_area);  % remove tiny blobs
end
