% M21_VSL2_arj_from_log.m
% Computes artifact rejection rates (familiar vs unfamiliar) from the
% M21 VSL2 pipeline log, flags subjects exceeding an overall rejection
% threshold, and runs a paired t-test comparing familiar vs unfamiliar.
%
% Bin structure (shape 1 only, both block orders combined):
%   Familiar   accepted = (b1+b2) + (b13+b14)   [triplet correct+incorrect, both orders]
%   Unfamiliar accepted = (b7+b8) + (b19+b20)   [foil correct+incorrect, both orders]
%   Max trials per computed bin = 32 (16 per block order x 2)
%
% Overall rejection rate (shape 1, collapsing familiar + unfamiliar):
%   overall_rej = (64 - fam_accepted - unfam_accepted) / 64 * 100
%
% Subjects are flagged if overall rejection exceeds ARJ_THRESHOLD.
% Behavioral outcome bins are collapsed before computing overall rate
% to avoid confounding poor performance with high artifact rejection.
%
% Usage:
%   Run from the directory containing the pipeline log file.
%   Edit LOG_FILE, EXCLUDE_SUBJECTS, and ARJ_THRESHOLD as needed.
%
% Output:
%   - Summary printed to command window
%   - Per-subject CSV saved to OUTPUT_CSV

% ── Configuration ─────────────────────────────────────────────────────────────

LOG_FILE         = 'M21_VSL2_pipeline_log.txt';
OUTPUT_CSV       = 'arj_summary_N66.csv';
EXCLUDE_SUBJECTS = {'S142'};   % known exclusions — add others here
ARJ_THRESHOLD    = 35;         % % overall rejection above which subject is flagged

% ── Parse pipeline log ────────────────────────────────────────────────────────

fid = fopen(LOG_FILE, 'r');
if fid == -1
    error('Cannot open log file: %s', LOG_FILE);
end
raw = fread(fid, '*char')';
fclose(fid);

[subj_tokens, subj_pos] = regexp(raw, '--- Subject (S\d+) ---', 'tokens', 'start');

subjects   = {};
fam_rej    = [];
unfam_rej  = [];
overall_rej = [];
flag       = [];

for i = 1:numel(subj_tokens)
    subj_id = subj_tokens{i}{1};

    if any(strcmp(subj_id, EXCLUDE_SUBJECTS))
        fprintf('Skipping excluded subject: %s\n', subj_id);
        continue;
    end

    % Extract this subject's block
    block_start = subj_pos(i);
    if i < numel(subj_pos)
        block_end = subj_pos(i+1) - 1;
    else
        block_end = numel(raw);
    end
    block = raw(block_start:block_end);

    % Extract Stage 6 bin counts
    tok = regexp(block, 'Stage 6: accepted trials per bin:\s*([\d\s]+)', 'tokens');
    if isempty(tok)
        fprintf('WARNING: No Stage 6 data for %s — skipping\n', subj_id);
        continue;
    end

    counts = str2num(strtrim(tok{1}{1})); %#ok<ST2NM>
    if numel(counts) ~= 24
        fprintf('WARNING: %s has %d bins (expected 24) — skipping\n', subj_id, numel(counts));
        continue;
    end

    % ── Familiar vs Unfamiliar (shape 1, binop equations) ─────────────────
    % Familiar:   b1+b2+b13+b14  (triplet correct+incorrect, both block orders)
    % Unfamiliar: b7+b8+b19+b20  (foil correct+incorrect, both block orders)
    fam_acc   = counts(1) + counts(2) + counts(13) + counts(14);
    unfam_acc = counts(7) + counts(8) + counts(19) + counts(20);

    fam_pct   = (32 - fam_acc)   / 32 * 100;
    unfam_pct = (32 - unfam_acc) / 32 * 100;

    % ── Overall rejection rate (shape 1, familiar + unfamiliar combined) ──
    % Max = 32 + 32 = 64 trials (both conditions, both block orders)
    % Collapsing behavioral outcome avoids confounding with performance.
    overall_pct = (64 - fam_acc - unfam_acc) / 64 * 100;

    subjects{end+1}    = subj_id; %#ok<AGROW>
    fam_rej(end+1)     = fam_pct; %#ok<AGROW>
    unfam_rej(end+1)   = unfam_pct; %#ok<AGROW>
    overall_rej(end+1) = overall_pct; %#ok<AGROW>
    flag(end+1)        = overall_pct > ARJ_THRESHOLD; %#ok<AGROW>
end

N = numel(subjects);

% ── Flagged subjects ──────────────────────────────────────────────────────────

flagged = subjects(logical(flag));
fprintf('\n=== Artifact Rejection Summary (N = %d) ===\n', N);
fprintf('Threshold: %.0f%%\n', ARJ_THRESHOLD);

if isempty(flagged)
    fprintf('\nNo subjects exceed the %.0f%% threshold.\n', ARJ_THRESHOLD);
else
    fprintf('\nSubjects flagged (overall rejection > %.0f%%):\n', ARJ_THRESHOLD);
    for i = 1:numel(flagged)
        idx = strcmp(subjects, flagged{i});
        fprintf('  %s: overall = %.1f%%  (familiar = %.1f%%, unfamiliar = %.1f%%)\n', ...
            flagged{i}, overall_rej(idx), fam_rej(idx), unfam_rej(idx));
    end
end

% ── Descriptive statistics ────────────────────────────────────────────────────

fprintf('\n--- Rejection rates (shape 1) ---\n');
fprintf('Familiar:   M = %.2f%%, SD = %.2f%%, range %.1f%%–%.1f%%\n', ...
    mean(fam_rej),   std(fam_rej),   min(fam_rej),   max(fam_rej));
fprintf('Unfamiliar: M = %.2f%%, SD = %.2f%%, range %.1f%%–%.1f%%\n', ...
    mean(unfam_rej), std(unfam_rej), min(unfam_rej), max(unfam_rej));
fprintf('Overall:    M = %.2f%%, SD = %.2f%%, range %.1f%%–%.1f%%\n', ...
    mean(overall_rej), std(overall_rej), min(overall_rej), max(overall_rej));

% ── Paired t-test: Familiar vs Unfamiliar ────────────────────────────────────

[~, p, ~, stats_out] = ttest(fam_rej, unfam_rej);
fprintf('\n--- Paired t-test: Familiar vs Unfamiliar ---\n');
fprintf('t(%d) = %.3f, p = %.4f\n', stats_out.df, stats_out.tstat, p);
if mean(fam_rej) > mean(unfam_rej)
    fprintf('Familiar rejection > Unfamiliar: observed familiarity effect is conservative.\n');
end

% ── Save CSV ──────────────────────────────────────────────────────────────────

fid_out = fopen(OUTPUT_CSV, 'w');
fprintf(fid_out, 'Subject,Familiar_rej_pct,Unfamiliar_rej_pct,Overall_rej_pct,Flagged\n');
for i = 1:N
    fprintf(fid_out, '%s,%.4f,%.4f,%.4f,%d\n', ...
        subjects{i}, fam_rej(i), unfam_rej(i), overall_rej(i), flag(i));
end
fclose(fid_out);

fprintf('\nPer-subject results saved to: %s\n', OUTPUT_CSV);
