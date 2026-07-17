%% =========================================================================
%  M21_VSL2_binop.m
%  Applies bin operations to individual subject .erp files, creating
%  derived bins (25-72) from the original averaged bins (1-24).
%
%  Input:  DATA/subjID/subjID_VSL2.erp          (pipeline output)
%  Output: DATA/subjID/subjID_VSL2_binop.erp    (with bins 1-72)
%
%  Also outputs:
%    M21_VSL2_binop_ICA_log.csv       — carried over from pipeline
%    M21_VSL2_binop_trial_counts.csv  — accepted trials for bins 1-24
%    M21_VSL2_binop_summary_stats.txt — means/ranges for Methods section
%
%  Requires: EEGLAB with ERPLAB plug-in
% =========================================================================

%% -------------------------------------------------------------------------
%  0. Housekeeping
% -------------------------------------------------------------------------
clear; clc;
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
ALLERP     = buildERPstruct([]);
CURRENTERP = 0;

%% -------------------------------------------------------------------------
%  1. Dialog
% -------------------------------------------------------------------------
prompt = { ...
    'StudyID (e.g. M21):', ...
    'TaskID (e.g. VSL2):', ...
    'Subject list file (one ID per line):', ...
    'Bin operations file — pass 1 (input 24 bins, output 36):', ...
    'Bin operations file — pass 2 (input 36 bins, output 68):', ...
    'Bin operations file — pass 3 (input 68 bins, output 72):', ...
    'Input ERP extension (after subjID_taskID, blank for none):', ...
    'Output ERP extension (after subjID_taskID):'};
dlgtitle = 'Bin operations parameters';
dims     = [1 72];
definput = {'M21', 'VSL2', 'm21_subjectlist1_all.txt', ...
    'm21_VSL2_binop_pass1.txt', 'm21_VSL2_binop_pass2.txt', 'm21_VSL2_binop_pass3.txt', ...
    '', 'binop'};
my_input = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(my_input)
    error('Cancelled by user.');
end

DIR      = pwd;
studyID  = strtrim(my_input{1});
taskID   = strtrim(my_input{2});
subj_list_fname = strtrim(my_input{3});
binop_pass1 = fullfile(DIR, strtrim(my_input{4}));
binop_pass2 = fullfile(DIR, strtrim(my_input{5}));
binop_pass3 = fullfile(DIR, strtrim(my_input{6}));
in_ext      = strtrim(my_input{7});   % blank → S101_VSL2.erp
out_ext     = strtrim(my_input{8});   % 'binop' → S101_VSL2_binop.erp

for bpf = {binop_pass1, binop_pass2, binop_pass3}
    if ~isfile(bpf{1})
        error('Bin operations file not found: %s', bpf{1});
    end
end
if ~isfile(subj_list_fname)
    error('Subject list file not found: %s', subj_list_fname);
end

subj_list = importdata(subj_list_fname);
nsubj     = length(subj_list);

if isempty(taskID)
    task_pfx = '';
else
    task_pfx = ['_' taskID];
end
study_tag = [studyID task_pfx];   % e.g. "M21_VSL2"

%% -------------------------------------------------------------------------
%  2. Open log file
% -------------------------------------------------------------------------
log_fname = fullfile(DIR, [study_tag '_binop_log.txt']);
fid_log   = fopen(log_fname, 'w');
if fid_log == -1
    error('Could not open log file for writing.');
end
fprintf(fid_log, 'Bin operations log — %s\n', study_tag);
fprintf(fid_log, 'Bin operations pass 1: %s\n', binop_pass1);
fprintf(fid_log, 'Bin operations pass 2: %s\n', binop_pass2);
fprintf(fid_log, 'Bin operations pass 3: %s\n', binop_pass3);
fprintf(fid_log, 'Run: %s\n\n', datestr(now));

%% -------------------------------------------------------------------------
%  3. Initialise trial count accumulator
%  (counts from the original bins 1-24 are preserved in the binop ERP)
% -------------------------------------------------------------------------
all_trial_counts     = [];
trial_header_written = false;
bin_labels           = {};
missing_subjects     = {};

%% =========================================================================
%  MAIN SUBJECT LOOP
% =========================================================================
for subject = 1:nsubj

    subjID      = strtrim(subj_list{subject});
    subject_DIR = fullfile(DIR, 'DATA', subjID);

    fprintf('\n==============================\n');
    fprintf('Subject %d / %d : %s\n', subject, nsubj, subjID);
    fprintf('==============================\n');
    fprintf(fid_log, '\n--- Subject %s ---\n', subjID);

    % Build input and output filenames
    if isempty(in_ext)
        in_fname  = [subjID task_pfx '.erp'];
    else
        in_fname  = [subjID task_pfx '_' in_ext '.erp'];
    end
    out_fname = [subjID task_pfx '_' out_ext '.erp'];
    out_erpname = [subjID task_pfx '_' out_ext];

    in_path  = fullfile(subject_DIR, in_fname);
    out_path = fullfile(subject_DIR, out_fname);

    % Check input file exists
    if ~isfile(in_path)
        fprintf(' *** WARNING: %s not found — skipping ***\n', in_fname);
        fprintf(fid_log, '  SKIPPED — %s not found\n', in_fname);
        missing_subjects{end+1} = subjID; %#ok<AGROW>
        continue
    end

    % ------------------------------------------------------------------
    %  Load input ERP
    % ------------------------------------------------------------------
    fprintf('  Loading %s\n', in_fname);
    ERP = pop_loaderp('filename', in_fname, 'filepath', subject_DIR);
    CURRENTERP         = CURRENTERP + 1;
    ALLERP(CURRENTERP) = ERP;
    erplab redraw;

    % ------------------------------------------------------------------
    %  Apply bin operations — three passes required
    %  pop_binoperator can only reference bins that exist in the INPUT
    %  ERP, not bins created earlier in the same file.
    %    Pass 1: input 24 bins  → output 36 bins  (derives 25-36 from 1-24)
    %    Pass 2: input 36 bins  → output 68 bins  (derives 37-68 from 25-36)
    %    Pass 3: input 68 bins  → output 72 bins  (derives 47-48, 57-60, 69-72)
    % ------------------------------------------------------------------
    fprintf('  Applying bin operations (pass 1: 24 → 36 bins)\n');
    ERP = pop_binoperator(ERP, binop_pass1);

    fprintf('  Applying bin operations (pass 2: 36 → 68 bins)\n');
    ERP = pop_binoperator(ERP, binop_pass2);

    fprintf('  Applying bin operations (pass 3: 68 → 72 bins)\n');
    ERP = pop_binoperator(ERP, binop_pass3);

    % ------------------------------------------------------------------
    %  Save output ERP
    % ------------------------------------------------------------------
    ERP.erpname = out_erpname;
    pop_savemyerp(ERP, ...
        'erpname',  ERP.erpname, ...
        'filename', out_fname, ...
        'filepath', subject_DIR, ...
        'warning',  'off');

    CURRENTERP         = CURRENTERP + 1;
    ALLERP(CURRENTERP) = ERP;
    erplab redraw;

    fprintf('  Saved: %s\n', out_fname);
    fprintf(fid_log, '  Applied bin operations → %s\n', out_fname);
    fprintf(fid_log, '  Total bins in output: %d\n', ERP.nbin);

    % ------------------------------------------------------------------
    %  Collect trial counts from original bins (1-24)
    %  These are preserved unchanged by pop_binoperator
    % ------------------------------------------------------------------
    if isfield(ERP, 'ntrials') && isfield(ERP.ntrials, 'accepted')

        % Original bins only (derived bins have no independent trial count)
        n_orig = min(24, ERP.nbin);
        counts = ERP.ntrials.accepted(1:n_orig);

        if isempty(all_trial_counts)
            all_trial_counts = counts;
        else
            all_trial_counts = [all_trial_counts; counts]; %#ok<AGROW>
        end

        % Write CSV header from first valid subject
        if ~trial_header_written
            if isfield(ERP, 'bindescr') && length(ERP.bindescr) >= n_orig
                bin_labels = ERP.bindescr(1:n_orig);
            else
                bin_labels = arrayfun(@(b) sprintf('Bin%d', b), ...
                    1:n_orig, 'UniformOutput', false);
            end
            % Write header to trial counts CSV
            trial_fname = fullfile(DIR, [study_tag '_binop_trial_counts.csv']);
            fid_trial   = fopen(trial_fname, 'w');
            if fid_trial == -1
                error('Could not open trial counts file for writing.');
            end
            fprintf(fid_trial, 'Subject');
            fprintf(fid_trial, ',%s', bin_labels{:});
            fprintf(fid_trial, '\n');
            trial_header_written = true;
        end

        fprintf(fid_trial, '%s', subjID);
        fprintf(fid_trial, ',%d', counts);
        fprintf(fid_trial, '\n');

        fprintf(fid_log, '  Trials accepted (bins 1-%d): %s\n', n_orig, num2str(counts));
    else
        fprintf(fid_log, '  ntrials.accepted not available\n');
    end

end  % subject loop

%% =========================================================================
%  Post-loop: summary statistics
% =========================================================================
if trial_header_written
    fclose(fid_trial);
end

%% Summary statistics file
sum_fname = fullfile(DIR, [study_tag '_binop_summary_stats.txt']);
fid_sum   = fopen(sum_fname, 'w');

fprintf(fid_sum, 'Summary statistics for Methods section\n');
fprintf(fid_sum, 'Study: %s   Task: %s\n', studyID, taskID);
fprintf(fid_sum, 'Run: %s\n\n', datestr(now));

if ~isempty(all_trial_counts)
    fprintf(fid_sum, '--- Accepted trials per condition (original bins 1-24) ---\n');
    for b = 1:size(all_trial_counts, 2)
        col = all_trial_counts(:, b);
        col = col(~isnan(col));
        if ~isempty(bin_labels)
            lbl = bin_labels{b};
        else
            lbl = sprintf('Bin %d', b);
        end
        fprintf(fid_sum, '  %s\n',              lbl);
        fprintf(fid_sum, '    N:     %d\n',     length(col));
        fprintf(fid_sum, '    Mean:  %.1f\n',   mean(col));
        fprintf(fid_sum, '    SD:    %.1f\n',   std(col));
        fprintf(fid_sum, '    Range: %d - %d\n', min(col), max(col));
    end
end

if ~isempty(missing_subjects)
    fprintf(fid_sum, '\n--- Missing subjects (%d) ---\n', numel(missing_subjects));
    fprintf(fid_sum, '  %s\n', strjoin(missing_subjects, ', '));
end

fclose(fid_sum);
fclose(fid_log);

fprintf('\n\nOutput files written to: %s\n', DIR);
fprintf('  %s\n', log_fname);
if trial_header_written
    fprintf('  %s\n', trial_fname);
end
fprintf('  %s\n', sum_fname);
fprintf('\nBin operations complete.\n');

%% =========================================================================
%  Run these separately after reviewing individual binop ERPs:
%    M21_VSL2_grand_average.m   (set f_ext to 'binop')
%    M21_VSL2_measure_amp.m     (set erp_ext to 'binop')
% =========================================================================
