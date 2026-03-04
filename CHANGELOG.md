# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [3.0] - 2026-03-03

### Added

- **Multi-pass segmentation v2** (`segment_DNAPL_v2.m`): Morphological reconstruction fills dark spots inside DNAPL without color thresholds
- **Streaming frame processing** (`load_frame.m`): On-demand frame loading, ~14 MB/frame instead of loading entire TIF stack into memory
- **Automated report generation** (`generate_report.m`): Outputs `.txt` and `.md` analysis reports with key metrics
- **Threshold locking**: First frame establishes GMM threshold, subsequent frames reuse it to prevent cluster flipping
- New segmentation methods: `gmm_v2`, `otsu_v2` (morphological hole recovery)
- Config parameter: `hole_fill_radius` for v2 segmentation

### Changed

- `characterize_solubilization_v2.m`: Uses locked threshold from frame 1 for all subsequent frames
- `config_pipeline.m`: TIF sorting changed from filename to modification date
- `validate_config.m`: Accepts `gmm_v2` and `otsu_v2` methods

### Fixed

- Memory overflow when processing large multi-page TIF stacks (>1000 frames)
- GMM cluster flipping causing Sn oscillations between 0.5 and 0.95

## [2.9] - 2026-02-28

### Added

- Interface analysis module (`analyze_interfaces.m`): Chain-code based DNAPL-water and DNAPL-solid interface detection
- Mass transfer estimation (`calculate_mass_transfer.m`)
- CAD-based flow domain verification
- Dual comparison script (`run_dual_comparison.m`)

### Changed

- Enhanced blob geometry analysis with shape classification (ganglia vs droplets)
- Improved visualization with 5 diagnostic figure generators

## [2.5] - 2026-02-24

### Added

- Initial public version
- Core pipeline: preprocessing → segmentation → analysis → visualization
- GMM, Otsu, Adaptive segmentation methods
- Flow domain extraction (color + morphology dual method)
- Saturation calculation, blob geometry analysis
- Time-series dissolution characterization
