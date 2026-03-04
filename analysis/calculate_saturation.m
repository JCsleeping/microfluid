function sat = calculate_saturation(dnapl_mask, flow_domain, pixel_size)
% CALCULATE_SATURATION  Compute DNAPL and water saturations.
%
%   sat = calculate_saturation(dnapl_mask, flow_domain, pixel_size)
%
%   Inputs:
%       dnapl_mask   - M x N logical (1 = DNAPL)
%       flow_domain  - M x N logical (1 = pore space)
%       pixel_size   - Physical size of one pixel [m] (optional)
%
%   Output:
%       sat - Struct with fields:
%           .Sn             DNAPL saturation [0-1]
%           .Sw             Water saturation [0-1]
%           .dnapl_area_px  DNAPL area [pixels]
%           .pore_area_px   Total pore area [pixels]
%           .dnapl_area_m2  DNAPL area [m^2] (if pixel_size given)
%           .pore_area_m2   Pore area [m^2]
%           .porosity       Image porosity (pore / total)

    if nargin < 3, pixel_size = []; end

    sat.dnapl_area_px = sum(dnapl_mask(:) & flow_domain(:));
    sat.pore_area_px  = sum(flow_domain(:));
    sat.Sn = sat.dnapl_area_px / max(sat.pore_area_px, 1);
    sat.Sw = 1 - sat.Sn;
    sat.porosity = sat.pore_area_px / numel(flow_domain);

    if ~isempty(pixel_size) && pixel_size > 0
        sat.dnapl_area_m2 = sat.dnapl_area_px * pixel_size^2;
        sat.pore_area_m2  = sat.pore_area_px  * pixel_size^2;
    else
        sat.dnapl_area_m2 = NaN;
        sat.pore_area_m2  = NaN;
    end
end
