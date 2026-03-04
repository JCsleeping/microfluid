function tests = test_extract_flow_domain_robustness
% Regression tests for flow-domain pillar detection robustness.
    tests = functiontests(localfunctions);
end


function test_default_frame_has_nonzero_pillars_and_no_contour_warning(testCase)
% Reproduces the "0% pillars + contour warning" issue on default data.
    root_dir = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(root_dir));

    old_vis = get(groot, 'defaultFigureVisible');
    set(groot, 'defaultFigureVisible', 'off');
    c = onCleanup(@() set(groot, 'defaultFigureVisible', old_vis)); %#ok<NASGU>

    config = config_pipeline( ...
        'preprocess.manual_crop_rect', [], ...
        'flow_domain_image', '', ...
        'pages', 1);

    tif_paths = config.multipage_tif_path;
    if ischar(tif_paths)
        tif_paths = {tif_paths};
    end

    [images, ~, ~] = read_multipage_tif(tif_paths{1}, config.pages);
    rgb_ref = images{1};
    [rgb_fd_rot, ~, ~] = rotate_and_crop(rgb_ref, config);

    lastwarn('');
    [flow_domain, solid_mask] = extract_flow_domain(rgb_fd_rot);
    [warn_msg, ~] = lastwarn;

    chip_mask = flow_domain | solid_mask;
    chip_area = sum(chip_mask(:));
    pillar_fraction = sum(solid_mask(:)) / max(chip_area, 1);

    verifyGreaterThan(testCase, pillar_fraction, 0.01);
    verifyFalse(testCase, contains(warn_msg, 'Contour not rendered'));

    close all force;
end
