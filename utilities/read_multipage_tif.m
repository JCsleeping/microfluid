function [images, num_pages, info] = read_multipage_tif(tif_path, pages)
% READ_MULTIPAGE_TIF  Read pages from a multi-page TIF file.
%
%   [images, num_pages, info] = read_multipage_tif(tif_path)
%   [images, num_pages, info] = read_multipage_tif(tif_path, pages)
%
%   Reads specified pages from a multi-page TIF. Returns a cell array of
%   uint8 RGB images. Handles 16-bit and grayscale conversion automatically.
%
%   Inputs:
%       tif_path - Path to the multi-page TIF file
%       pages    - (optional) Vector of 1-based page indices to read.
%                  [] or omitted = read ALL pages.
%                  e.g. [1, 10, 20, 72] reads only those 4 pages.
%
%   Outputs:
%       images    - 1 x N cell array of uint8 RGB images (M x K x 3)
%       num_pages - Total number of pages in the TIF file
%       info      - struct array from imfinfo (metadata for all pages)
%
%   Examples:
%       % Read all pages
%       [imgs, n] = read_multipage_tif('experiment.tif');
%
%       % Read only pages 1, 36, 72
%       [imgs, n] = read_multipage_tif('experiment.tif', [1 36 72]);
%
%       % Read every 10th page
%       [~, n] = read_multipage_tif('experiment.tif', []);
%       [imgs, ~] = read_multipage_tif('experiment.tif', 1:10:n);

    if ~isfile(tif_path)
        error('read_multipage_tif:notFound', 'TIF file not found: %s', tif_path);
    end

    %% Get file info
    fprintf('  Reading TIF info: %s\n', tif_path);
    info = imfinfo(tif_path);
    num_pages = numel(info);
    fprintf('  Total pages: %d  |  Size: %d x %d  |  BitDepth: %d\n', ...
        num_pages, info(1).Height, info(1).Width, info(1).BitDepth);

    %% Determine which pages to read
    if nargin < 2 || isempty(pages)
        pages = 1:num_pages;
    end

    % Validate page indices
    pages = pages(:)';  % row vector
    if any(pages < 1) || any(pages > num_pages)
        error('read_multipage_tif:badPage', ...
            'Page indices must be between 1 and %d. Got range [%d, %d].', ...
            num_pages, min(pages), max(pages));
    end

    %% Memory estimation
    n_read = numel(pages);
    bytes_per_page = double(info(1).Height) * double(info(1).Width) * 3;
    est_bytes = n_read * bytes_per_page;
    est_mb = est_bytes / 1024^2;
    fprintf('  Estimated memory: %.0f MB for %d pages\n', est_mb, n_read);

    try
        mem_info = memory();  % Windows-only
        avail_bytes = mem_info.MemAvailableAllArrays;
        if est_bytes > 0.8 * avail_bytes
            warning('read_multipage_tif:memoryRisk', ...
                ['Estimated %.0f MB needed but only %.0f MB available. ' ...
                 'Consider using config.pages to select a subset.'], ...
                est_mb, avail_bytes / 1024^2);
        end
    catch
        % memory() is Windows-only; silently skip on other platforms
    end

    %% Read pages
    images = cell(1, n_read);

    fprintf('  Reading %d pages: ', n_read);
    for k = 1:n_read
        p = pages(k);
        img = imread(tif_path, p);

        % Handle 16-bit → 8-bit
        if isa(img, 'uint16')
            img = im2uint8(img);
        end

        % Handle grayscale → RGB
        if size(img, 3) == 1
            img = repmat(img, [1 1 3]);
        end

        images{k} = img;

        % Progress indicator
        if n_read <= 20 || mod(k, ceil(n_read/20)) == 0 || k == n_read
            fprintf('%d', p);
            if k < n_read, fprintf(', '); end
        end
    end
    fprintf('\n  Done.\n');
end
