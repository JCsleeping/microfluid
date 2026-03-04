function blob = analyze_blob_geometry(dnapl_mask, pixel_size)
% ANALYZE_BLOB_GEOMETRY  Compute geometric properties of connected DNAPL blobs.
%
%   blob = analyze_blob_geometry(dnapl_mask, pixel_size)
%
%   Inputs:
%       dnapl_mask - M x N logical DNAPL mask
%       pixel_size - Physical pixel size [m] (optional, can be [])
%
%   Output:
%       blob - Struct with fields:
%           .num_blobs          Number of connected blobs
%           .labeled_image      uint32 labeled image
%           .props              struct array from regionprops + derived metrics
%           .blob_table         Table of per-blob properties
%           .size_distribution  Summary statistics struct

    if nargin < 2, pixel_size = []; end

    %% Label connected components (8-connectivity)
    cc = bwconncomp(dnapl_mask, 8);
    blob.labeled_image = uint32(labelmatrix(cc));
    blob.num_blobs = cc.NumObjects;

    if blob.num_blobs == 0
        blob.props = struct([]);
        blob.blob_table = table();
        blob.size_distribution = struct('mean',0,'median',0,'std',0,'min',0,'max',0);
        return;
    end

    %% Compute standard properties
    props = regionprops(cc, 'Area', 'Perimeter', 'Centroid', ...
        'BoundingBox', 'MajorAxisLength', 'MinorAxisLength', ...
        'Eccentricity', 'Orientation', 'EquivDiameter', 'Solidity', ...
        'ConvexArea', 'FilledArea');

    %% Compute derived metrics
    for i = 1:blob.num_blobs
        P = props(i).Perimeter;
        A = props(i).Area;

        % Circularity (1 = perfect circle)
        props(i).Circularity = 4 * pi * A / (P^2 + eps);

        % Aspect ratio
        props(i).AspectRatio = props(i).MajorAxisLength / ...
            max(props(i).MinorAxisLength, eps);

        % Compactness (area / convex area)
        props(i).Compactness = A / max(props(i).ConvexArea, 1);

        % Physical units
        if ~isempty(pixel_size) && pixel_size > 0
            props(i).Area_m2          = A * pixel_size^2;
            props(i).Perimeter_m      = P * pixel_size;
            props(i).EquivDiameter_m  = props(i).EquivDiameter * pixel_size;
        else
            props(i).Area_m2          = NaN;
            props(i).Perimeter_m      = NaN;
            props(i).EquivDiameter_m  = NaN;
        end

        % Ganglia classification (Mayer & Miller, 1996 style)
        % Physical thresholds: singlet < 50 um^2, ganglion < 5000 um^2
        if ~isempty(pixel_size) && pixel_size > 0
            area_um2 = A * (pixel_size * 1e6)^2;  % convert m^2 to um^2
            if area_um2 < 50
                props(i).GangliaType = "singlet";
            elseif area_um2 < 5000
                props(i).GangliaType = "ganglion";
            else
                props(i).GangliaType = "pool";
            end
        else
            % Fallback: pixel-based thresholds (legacy behavior)
            if A < 50
                props(i).GangliaType = "singlet";
            elseif A < 500
                props(i).GangliaType = "ganglion";
            else
                props(i).GangliaType = "pool";
            end
        end
    end

    blob.props = props;

    %% Build table
    BlobID = (1:blob.num_blobs)';
    Area = [props.Area]';
    Perimeter = [props.Perimeter]';
    Circularity = [props.Circularity]';
    AspectRatio = [props.AspectRatio]';
    Eccentricity = [props.Eccentricity]';
    Solidity = [props.Solidity]';
    EquivDiameter = [props.EquivDiameter]';
    Compactness = [props.Compactness]';
    GangliaType = [props.GangliaType]';
    Centroid_X = cellfun(@(c) c(1), {props.Centroid})';
    Centroid_Y = cellfun(@(c) c(2), {props.Centroid})';

    blob.blob_table = table(BlobID, Area, Perimeter, Circularity, ...
        AspectRatio, Eccentricity, Solidity, EquivDiameter, Compactness, ...
        Centroid_X, Centroid_Y, GangliaType);

    %% Size distribution statistics
    areas = [props.Area];
    blob.size_distribution.mean   = mean(areas);
    blob.size_distribution.median = median(areas);
    blob.size_distribution.std    = std(areas);
    blob.size_distribution.min    = min(areas);
    blob.size_distribution.max    = max(areas);
    blob.size_distribution.total  = sum(areas);
end
