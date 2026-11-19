# preference_choice_mixed_models

MATLAB scripts for analyzing the association between ADHD traits and preference-choice consistency in everyday item selection, using trial-level mixed-effects models.

## Overview

Participants rated their preference for 144 everyday items (12 categories x 12 items, 7-point scale). They then chose between 72 pairs of items from the same category, which were built from their own ratings: 24 far-distance, 24 medium-distance and 24 near-distance pairs. Preference-choice consistency is whether the participant chose the item they had rated higher.

The scripts perform the following analyses:

1. Load the trial data of each participant and match them to the questionnaire scores
2. Assign the distance conditions (far, medium, near) and exclude trials with tied ratings
3. Compute participant-level descriptive measures for each distance condition (consistency, actual rating difference, response time, number of analysed trials)
4. Compute rating-spread indices (within-category SD and between-category SD of the preference ratings)
5. Fit trial-level GLMMs of preference-choice consistency (Models 1-5)
6. Fit LMMs of the actual rating difference and log response time
7. Test fixed effects with likelihood-ratio tests and save the results to Excel files

## Directory Structure

    preference_choice_mixed_models/
    ├── Questionnaire.xlsx            # Place questionnaire file here
    ├── Input/                        # Place trial files here
    ├── Results/                      # Created automatically; results are saved here
    ├── summarize_participants.m
    └── fit_mixed_models.m

Note: The `.gitkeep` file in the Input directory is used to maintain the directory structure in GitHub. It can be safely kept or deleted after downloading the repository - it does not affect the scripts' functionality.

## Requirements

### Required Software
- MATLAB R2017b or later
- Statistics and Machine Learning Toolbox (fitglme, fitlme)

No external functions are required.

## Input File Specifications

The data are available from the corresponding author upon reasonable request. The scripts expect the following format.

### Trial files (Input/*_Analysis02.xlsx, sheet Sheet1)

- One file per participant
- Each choice trial occupies two rows, one per item (144 rows; each item appears once)
- The digits of the participant ID must appear in the file name (alternatively, the file can have a subjectID column)
- Required columns:
  - Preference: preference rating of the item in this row (1-7)
  - Category: item category
  - Preference03: distance condition of the pair (three codes; the code with the largest mean rating difference is treated as far, the smallest as near)
  - Distance: absolute rating difference between the two items of the pair
  - Consistensy: 1 = higher-rated item chosen, 2 = lower-rated item chosen, 3 = tied ratings (spelled as in the data files)
  - rt: choice response time (ms)
- The two rows of a trial are paired using the counter column, the number column, or Category + rt, whichever is present and gives 72 pairs

### Questionnaire file (Questionnaire.xlsx, sheet Sheet1)

- One row per participant
- The header row is the first row that contains both ID and ASRS
- Required columns:
  - ID: participant ID (contains the digits used in the trial file names)
  - Age: age in years
  - Sex: F or M
  - ASRS, A, B: ASRS total, Part A and Part B scores
  - BIS, BAS: BIS and BAS scale scores
  - SSS: SSS-AE total score
- Optional columns (read if present): Drive, Rew Res, Fun Seek (BAS subscales); TAS, Dis, ES (SSS-AE subscales)

## Usage

1. Place Questionnaire.xlsx in the same directory as the scripts
2. Place the trial files in the Input directory
3. Set the MATLAB current folder to this directory
4. Run summarize_participants.m (participant-level summary)
5. Run fit_mixed_models.m (mixed-effects models)

The two scripts are independent and can be run in either order.

## Key Parameters

The following parameters can be adjusted in the SETTINGS block at the top of each script:

- `CFG.trialDir`: Directory of the trial files (default: Input)
- `CFG.trialPattern`: File name pattern of the trial files (default: *_Analysis02.xlsx)
- `CFG.trialSheet`: Sheet name of the trial files (default: Sheet1)
- `CFG.questFile`: Questionnaire file (default: Questionnaire.xlsx)
- `CFG.questSheet`: Sheet name of the questionnaire file (default: Sheet1)
- `CFG.resultDir`: Output directory (default: Results)
- `CFG.nTrials`: Number of choice trials per participant (default: 72)
- `CFG.condVar`: Column coding the distance condition of each pair (default: Preference03)

## Analysis Settings

- Trials in which the two items had identical ratings are excluded
- Consistency (1/0) is analysed with binomial GLMMs (logit link, Laplace approximation); the actual rating difference and log response time are analysed with LMMs (maximum likelihood)
- Distance is effects-coded: C_far = far 1, medium 0, near -1; C_medium = far 0, medium 1, near -1
- ASRS, BIS, BAS and SSS-AE scores are z-standardized across participants; sex is coded female +0.5, male -0.5
- Random effects: by-participant random intercepts and slopes for the within-participant predictor, and by-category random intercepts; if a model does not converge, it is refitted with intercepts only (reported in the ModelInfo sheet)
- Fixed effects are tested with likelihood-ratio tests; the two distance terms and the two interaction terms are tested jointly
- Coefficients are reported with Wald 95% confidence intervals

## Output Files

All outputs are saved in the Results/ directory:

- participant_summary.xlsx: Participant-level measures (sheets Long, Wide, LabelCoding)
- mixed_models.xlsx: Model results (sheets ModelInfo, LRT, Coefficients, SimpleSlopes_RatingDiff, RandomEffects)
- participant_summary_log.txt, mixed_models_log.txt: Log files (UTF-8)

## Important Notes

- The Statistics and Machine Learning Toolbox is required
- Set the MATLAB current folder to this directory before running the scripts
- The log files list the names of the trial files; do not share them if the file names contain identifying information
- The Pearson correlations and the t-test reported in the paper were computed in IBM SPSS Statistics from the Wide sheet of participant_summary.xlsx

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Citation

If you use these scripts in your research, please cite the following paper:

(Under Review)
