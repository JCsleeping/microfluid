function mt = calculate_mass_transfer(iface_results, sat_results, blob_results, config)
% CALCULATE_MASS_TRANSFER  Estimate DNAPL mass transfer rate.
%
%   mt = calculate_mass_transfer(iface_results, sat_results, blob_results, config)
%
%   Uses measured specific interfacial area and Sherwood number correlations
%   to estimate the lumped mass transfer coefficient and dissolution rate.
%
%   Inputs:
%       iface_results - Output from analyze_interfaces
%       sat_results   - Output from calculate_saturation
%       blob_results  - Output from analyze_blob_geometry
%       config        - Pipeline configuration struct
%
%   Output:
%       mt - Struct with fields:
%           .sherwood_number
%           .mass_transfer_coeff_kL   [m/s]
%           .specific_interfacial_area [m^-1]
%           .mass_transfer_rate       [kg/m^3/s]
%           .driving_force_Cs         [mg/L]
%           .characteristic_length    [m]
%           .model_used

    D   = config.physical.diffusion_coeff;   % [m^2/s]
    Cs  = config.physical.solubility;        % [mg/L]
    px  = config.physical.pixel_size;        % [m/pixel]
    correlation = config.physical.sherwood_correlation;

    %% Characteristic length scale
    if blob_results.num_blobs > 0 && ~isnan(blob_results.props(1).EquivDiameter_m)
        d_char = mean([blob_results.props.EquivDiameter_m]);
    else
        % Fallback: use mean equiv diameter in pixels * pixel_size
        if blob_results.num_blobs > 0
            d_char = mean([blob_results.props.EquivDiameter]) * px;
        else
            d_char = px * 10;  % arbitrary small value
        end
    end

    %% Sherwood number correlation
    Sn = sat_results.Sn;

    switch lower(correlation)
        case 'powers'
            % Powers et al. (1994) — empirical for residual NAPL dissolution
            % Sh = 4.0 * Sn^(-0.6) (simplified for low Re)
            Sh = 4.0 * max(Sn, 0.001)^(-0.6);

        case 'wilson'
            % Wilson & Geankoplis — modified for porous media
            % Sh = 2 + 0.6 * Sn^0.5
            Sh = 2 + 0.6 * max(Sn, 0.001)^0.5;

        case 'interfacial'
            % Direct: assume Sh = 2 (sphere in infinite medium)
            Sh = 2;

        otherwise
            warning('calculate_mass_transfer:unknownCorrelation', ...
                'Unknown Sherwood correlation "%s". Using Sh = 2.', correlation);
            Sh = 2;
    end

    %% Mass transfer coefficient
    kL = Sh * D / max(d_char, eps);  % [m/s]

    %% Mass transfer rate
    % J = kL * a_nw * (Cs - C_bulk), assuming C_bulk << Cs
    a_nw = iface_results.specific_interfacial_area;  % [m^-1]
    Cs_kg_m3 = Cs * 1e-3;  % mg/L → kg/m^3 (1 mg/L = 1e-3 kg/m^3)
    J = kL * a_nw * Cs_kg_m3;  % [kg/m^3/s]

    %% Store results
    mt.sherwood_number         = Sh;
    mt.mass_transfer_coeff_kL  = kL;
    mt.specific_interfacial_area = a_nw;
    mt.mass_transfer_rate      = J;
    mt.driving_force_Cs        = Cs;
    mt.characteristic_length   = d_char;
    mt.model_used              = correlation;

    fprintf('  Mass transfer: Sh = %.2f, kL = %.2e m/s, J = %.2e kg/m3/s\n', Sh, kL, J);
end
