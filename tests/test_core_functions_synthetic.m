function tests = test_core_functions_synthetic
% TEST_CORE_FUNCTIONS_SYNTHETIC  Unit tests using synthetic data.
%   No real experimental data required. Tests core analysis functions
%   with programmatically generated inputs.
%
%   Run with:  runtests('test_core_functions_synthetic')

    tests = functiontests(localfunctions);
end


%% ========== validate_config ==========

function test_validate_config_accepts_valid_defaults(testCase)
    setup_path();
    config = config_pipeline();
    verifyTrue(testCase, isstruct(config));
end

function test_validate_config_rejects_negative_pixel_size(testCase)
    setup_path();
    verifyError(testCase, ...
        @() config_pipeline('physical.pixel_size', -1), ...
        'validate_config:badParam');
end

function test_validate_config_rejects_zero_pixel_size(testCase)
    setup_path();
    verifyError(testCase, ...
        @() config_pipeline('physical.pixel_size', 0), ...
        'validate_config:badParam');
end

function test_validate_config_rejects_negative_morph_radius(testCase)
    setup_path();
    verifyError(testCase, ...
        @() config_pipeline('segmentation.morph_radius', -1), ...
        'validate_config:badParam');
end

function test_validate_config_rejects_zero_min_blob_area(testCase)
    setup_path();
    verifyError(testCase, ...
        @() config_pipeline('segmentation.min_blob_area', 0), ...
        'validate_config:badParam');
end

function test_validate_config_rejects_bad_input_mode(testCase)
    setup_path();
    verifyError(testCase, ...
        @() config_pipeline('input_mode', 'invalid'), ...
        'validate_config:badParam');
end

function test_validate_config_rejects_fractional_pages(testCase)
    setup_path();
    verifyError(testCase, ...
        @() config_pipeline('pages', [1, 2.5, 3]), ...
        'validate_config:badParam');
end


%% ========== calculate_saturation ==========

function test_saturation_full_dnapl(testCase)
    setup_path();
    flow_domain = true(100, 100);
    dnapl_mask = true(100, 100);
    sat = calculate_saturation(dnapl_mask, flow_domain, 1e-6);
    verifyEqual(testCase, sat.Sn, 1.0, 'AbsTol', 1e-10);
    verifyEqual(testCase, sat.Sw, 0.0, 'AbsTol', 1e-10);
end

function test_saturation_no_dnapl(testCase)
    setup_path();
    flow_domain = true(100, 100);
    dnapl_mask = false(100, 100);
    sat = calculate_saturation(dnapl_mask, flow_domain, 1e-6);
    verifyEqual(testCase, sat.Sn, 0.0, 'AbsTol', 1e-10);
    verifyEqual(testCase, sat.Sw, 1.0, 'AbsTol', 1e-10);
end

function test_saturation_half_filled(testCase)
    setup_path();
    flow_domain = true(100, 100);
    dnapl_mask = false(100, 100);
    dnapl_mask(1:50, :) = true;
    sat = calculate_saturation(dnapl_mask, flow_domain, 1e-6);
    verifyEqual(testCase, sat.Sn, 0.5, 'AbsTol', 1e-10);
end

function test_saturation_respects_flow_domain(testCase)
    setup_path();
    flow_domain = false(100, 100);
    flow_domain(1:50, :) = true;
    dnapl_mask = true(100, 100);
    sat = calculate_saturation(dnapl_mask, flow_domain, 1e-6);
    % DNAPL outside flow domain should not count; Sn = 1.0 within pore
    verifyEqual(testCase, sat.Sn, 1.0, 'AbsTol', 1e-10);
    verifyEqual(testCase, sat.dnapl_area_px, 5000);
end


%% ========== refine_mask ==========

function test_refine_mask_removes_small_blobs(testCase)
    setup_path();
    mask = false(100, 100);
    mask(10, 10) = true;           % 1-pixel blob (below min_blob_area=10)
    mask(50:60, 50:60) = true;     % 121-pixel blob
    cleaned = refine_mask(mask, 2, 10);
    % Small blob should be removed; large blob should remain (possibly modified)
    verifyGreaterThan(testCase, sum(cleaned(:)), 0);
    verifyEqual(testCase, cleaned(10, 10), false);
end

function test_refine_mask_zero_radius(testCase)
    setup_path();
    mask = true(50, 50);
    cleaned = refine_mask(mask, 0, 1);
    verifyEqual(testCase, sum(cleaned(:)), 2500);
end


%% ========== analyze_blob_geometry ==========

function test_blob_geometry_empty_mask(testCase)
    setup_path();
    mask = false(100, 100);
    blob = analyze_blob_geometry(mask, 1e-6);
    verifyEqual(testCase, blob.num_blobs, 0);
    verifyTrue(testCase, isempty(blob.props));
end

function test_blob_geometry_single_blob(testCase)
    setup_path();
    mask = false(100, 100);
    mask(40:60, 40:60) = true;  % 21x21 square blob = 441 px
    blob = analyze_blob_geometry(mask, 1e-6);
    verifyEqual(testCase, blob.num_blobs, 1);
    verifyEqual(testCase, blob.props(1).Area, 441);
    verifyGreaterThan(testCase, blob.props(1).Area_m2, 0);
end

function test_blob_geometry_ganglia_with_pixel_size(testCase)
    setup_path();
    % pixel_size = 1e-6 m/px → 1 px = 1 um^2
    % singlet < 50 um^2, ganglion < 5000 um^2
    mask = false(200, 200);
    % Small blob: 3x3 = 9 px = 9 um^2 → singlet
    mask(10:12, 10:12) = true;
    % Medium blob: 30x30 = 900 px = 900 um^2 → ganglion
    mask(50:79, 50:79) = true;
    % Large blob: 80x80 = 6400 px = 6400 um^2 → pool
    mask(100:179, 100:179) = true;

    blob = analyze_blob_geometry(mask, 1e-6);
    types = [blob.props.GangliaType];
    verifyTrue(testCase, any(types == "singlet"));
    verifyTrue(testCase, any(types == "ganglion"));
    verifyTrue(testCase, any(types == "pool"));
end

function test_blob_geometry_ganglia_without_pixel_size(testCase)
    setup_path();
    % Without pixel_size, uses legacy pixel thresholds (50, 500)
    mask = false(200, 200);
    mask(10, 10) = true;           % 1 px → singlet
    mask(50:59, 50:59) = true;     % 100 px → ganglion
    mask(100:179, 100:179) = true; % 6400 px → pool

    blob = analyze_blob_geometry(mask, []);
    types = [blob.props.GangliaType];
    verifyTrue(testCase, any(types == "singlet"));
    verifyTrue(testCase, any(types == "ganglion"));
    verifyTrue(testCase, any(types == "pool"));
end


%% ========== Helper ==========

function setup_path()
    root_dir = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(root_dir));
end
