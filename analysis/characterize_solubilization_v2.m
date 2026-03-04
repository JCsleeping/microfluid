function sol = characterize_solubilization_v2(frame_index, flow_domain, time_vector, config)
% CHARACTERIZE_SOLUBILIZATION_V2  Track DNAPL dissolution across a time series.
%
%   sol = characterize_solubilization_v2(frame_index, flow_domain, time_vector, config)
%
%   Uses lazy loading: frames are loaded one-by-one via load_frame() to
%   avoid holding all images in memory simultaneously.
%
%   Inputs:
%       frame_index  - Struct array with fields .tif_path, .page (from pipeline)
%       flow_domain  - M x N logical pore-space mask (constant)
%       time_vector  - 1 x N time stamps [s or PV]
%       config       - Pipeline configuration struct
%
%   Output:
%       sol - Struct with time-series results:
%           .saturation_vs_time, .num_blobs_vs_time, .mean_blob_size_vs_time,
%           .interface_area_vs_time, .dissolution_rate, .fitted_model,
%           .change, .mass_dissolved, .masks

    num_frames = numel(frame_index);
    px = config.physical.pixel_size;

    %% Preallocate
    sol.saturation_vs_time     = zeros(num_frames, 1);
    sol.num_blobs_vs_time      = zeros(num_frames, 1);
    sol.mean_blob_size_vs_time = zeros(num_frames, 1);
    sol.interface_area_vs_time = zeros(num_frames, 1);
    sol.masks                  = cell(num_frames, 1);

    %% Process each frame
    for t = 1:num_frames
        fprintf('\n  --- Frame %d / %d ---\n', t, num_frames);

        % Load frame on-demand (keeps only 1 frame in memory)
        rgb = load_frame(t, frame_index);
        [rgb_rot, ~, ~] = rotate_and_crop(rgb, config);
        [rgb_corr, ~]   = correct_illumination(rgb_rot, ...
            config.illumination.method, config.illumination);

        % Align to flow domain size
        if size(rgb_corr,1) ~= size(flow_domain,1) || size(rgb_corr,2) ~= size(flow_domain,2)
            rgb_corr = imresize(rgb_corr, size(flow_domain));
        end

        % Segment — lock threshold after frame 1 to prevent cluster flipping
        if t == 1
            % Frame 1: fit GMM/Otsu normally to establish threshold
            if endsWith(config.segmentation.method, '_v2')
                [dnapl_mask, ~, seg_info_t] = segment_DNAPL_v2(rgb_corr, flow_domain, config);
            else
                [dnapl_mask, ~, seg_info_t] = segment_DNAPL(rgb_corr, flow_domain, config);
            end
            locked_threshold = seg_info_t.threshold;
            fprintf('  >> Threshold locked at %.4f (from frame 1)\n', locked_threshold);
        else
            % Subsequent frames: use the locked threshold
            config_locked = config;
            config_locked.segmentation.fixed_threshold = locked_threshold;
            if endsWith(config.segmentation.method, '_v2')
                [dnapl_mask, ~, ~] = segment_DNAPL_v2(rgb_corr, flow_domain, config_locked);
            else
                [dnapl_mask, ~, ~] = segment_DNAPL(rgb_corr, flow_domain, config_locked);
            end
        end
        sol.masks{t} = dnapl_mask;

        % Saturation
        sat = calculate_saturation(dnapl_mask, flow_domain, px);
        sol.saturation_vs_time(t) = sat.Sn;

        % Blob geometry
        blob = analyze_blob_geometry(dnapl_mask, px);
        sol.num_blobs_vs_time(t) = blob.num_blobs;
        sol.mean_blob_size_vs_time(t) = blob.size_distribution.mean;

        % Interface
        iface = analyze_interfaces(dnapl_mask, flow_domain, px, config);
        sol.interface_area_vs_time(t) = iface.dnapl_water_length_px;
    end

    %% Dissolution rate: dSn/dt
    dt = diff(time_vector(:));
    dt(dt == 0) = 1;  % avoid division by zero
    sol.dissolution_rate = diff(sol.saturation_vs_time) ./ dt;

    %% Change detection between consecutive frames
    sol.change = struct('dissolved_px', [], 'appeared_px', [], 'net_px', []);
    for t = 2:num_frames
        dissolved  = sol.masks{t-1} &  ~sol.masks{t};
        appeared   = ~sol.masks{t-1} &  sol.masks{t};
        sol.change(t-1).dissolved_px = sum(dissolved(:));
        sol.change(t-1).appeared_px  = sum(appeared(:));
        sol.change(t-1).net_px       = sol.change(t-1).appeared_px - sol.change(t-1).dissolved_px;
    end

    %% Cumulative mass dissolved estimate
    depth = config.physical.depth;
    rho   = config.physical.dnapl_density;
    pore_vol = sum(flow_domain(:)) * px^2 * depth;  % [m^3]
    sol.mass_dissolved = (sol.saturation_vs_time(1) - sol.saturation_vs_time(end)) ...
                         * pore_vol * rho;  % [kg]

    fprintf('\n  Solubilization complete. Sn: %.3f -> %.3f (%.1f%% removed)\n', ...
        sol.saturation_vs_time(1), sol.saturation_vs_time(end), ...
        100 * (1 - sol.saturation_vs_time(end) / max(sol.saturation_vs_time(1), eps)));
end
