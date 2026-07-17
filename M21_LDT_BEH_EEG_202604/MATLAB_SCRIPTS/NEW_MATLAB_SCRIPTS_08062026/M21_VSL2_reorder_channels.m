%% =========================================================================
%  M21_VSL2_reorder_channels.m
%  Reorders channels in all subject .erp files to match a canonical
%  channel order defined by label matching.
%
%  The problem: when clean_artifacts() removed and eeg_interp() restored
%  a channel, EEGLAB appended it at the end of the channel array rather
%  than restoring it to its original position. This means channel index N
%  refers to different electrodes in different subjects.
%
%  The fix: for each subject, find the permutation that maps their current
%  channel order to the canonical order (by label), then reorder
%  ERP.bindata, ERP.binerror, and ERP.chanlocs accordingly.
%
%  Canonical order is taken from the reference subject (first subject in
%  the list whose channel labels are a permutation of the canonical set).
%
%  Applies to both the basic averaged .erp and the binop .erp files.
%
%  Output: overwrites each .erp file in place (originals backed up as
%  subjID_VSL2_orig.erp and subjID_VSL2_binop_orig.erp)
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
    'Subject list file:', ...
    'ERP extensions to fix (space-separated, e.g.  VSL2 VSL2_binop):'};
dlgtitle = 'Channel reorder parameters';
dims     = [1 72];
definput = {'M21', 'VSL2', 'm21_subjectlist1_all.txt', 'VSL2 VSL2_binop'};
my_input = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(my_input), error('Cancelled.'); end

DIR       = pwd;
studyID   = strtrim(my_input{1});
taskID    = strtrim(my_input{2});
subj_list = importdata(strtrim(my_input{3}));
nsubj     = length(subj_list);
erp_exts  = strsplit(strtrim(my_input{4}));  % e.g. {'VSL2', 'VSL2_binop'}

%% -------------------------------------------------------------------------
%  2. Define canonical channel order
%  Taken from S101 which had no channels removed and therefore retains
%  the original recording order.
% -------------------------------------------------------------------------
% Canonical order taken directly from reref_eq_brainvision_hampshire.txt
% nch1-nch32 defines the authoritative channel positions for this cap.
% Note: FP2 is at position 27 (not 32); non-EEG channels are 28-32.
canonical_labels = { ...
    'FP1', 'Fz', 'F3', 'F7', 'FC5', 'FC1', 'C3', 'T7', ...
    'CP5', 'CP1', 'Pz', 'P3', 'P7', 'O1', 'O2', 'P4', ...
    'P8', 'CP6', 'CP2', 'CZ', 'C4', 'T8', 'FC6', 'FC2', ...
    'F4', 'F8', 'FP2', 'Mastoid R', 'Mastoid L', 'HEOG R', 'HEOG L', 'VEOG L'};

n_canonical = length(canonical_labels);
fprintf('Canonical order: %d channels\n', n_canonical);
fprintf('Reference labels: %s\n\n', strjoin(canonical_labels, ', '));

%% -------------------------------------------------------------------------
%  3. Open log file
% -------------------------------------------------------------------------
log_fname = fullfile(DIR, [studyID '_' taskID '_reorder_log.txt']);
fid_log   = fopen(log_fname, 'w');
fprintf(fid_log, 'Channel reorder log — %s %s\n', studyID, taskID);
fprintf(fid_log, 'Run: %s\n', datestr(now));
fprintf(fid_log, 'Canonical order: %s\n\n', strjoin(canonical_labels, ', '));

%% =========================================================================
%  MAIN LOOP
% =========================================================================
n_fixed    = 0;
n_skipped  = 0;
n_already  = 0;

for subject = 1:nsubj
    subjID      = strtrim(subj_list{subject});
    subject_DIR = fullfile(DIR, 'DATA', subjID);

    fprintf('\n==============================\n');
    fprintf('Subject %d / %d : %s\n', subject, nsubj, subjID);
    fprintf('==============================\n');
    fprintf(fid_log, '\n--- Subject %s ---\n', subjID);

    for e = 1:length(erp_exts)
        ext      = erp_exts{e};
        fname    = [subjID '_' ext '.erp'];
        fpath    = fullfile(subject_DIR, fname);
        fname_bk = [subjID '_' ext '_orig.erp'];
        fpath_bk = fullfile(subject_DIR, fname_bk);

        if ~isfile(fpath)
            fprintf('  [%s] NOT FOUND — skipping\n', ext);
            fprintf(fid_log, '  [%s] not found\n', ext);
            n_skipped = n_skipped + 1;
            continue
        end

        % Load ERP
        ERP = pop_loaderp('filename', fname, 'filepath', subject_DIR);
        current_labels = {ERP.chanlocs.labels};

        % Check label set matches canonical (same labels, possibly different order)
        if length(current_labels) ~= n_canonical
            fprintf('  [%s] WARNING: has %d channels, expected %d — skipping\n', ...
                ext, length(current_labels), n_canonical);
            fprintf(fid_log, '  [%s] SKIPPED: channel count mismatch (%d vs %d)\n', ...
                ext, length(current_labels), n_canonical);
            n_skipped = n_skipped + 1;
            continue
        end

        % Check if already in canonical order
        if isequal(current_labels, canonical_labels)
            fprintf('  [%s] already in canonical order — no change\n', ext);
            fprintf(fid_log, '  [%s] already correct\n', ext);
            n_already = n_already + 1;
            continue
        end

        % Build reindex vector: reorder(i) = position of canonical_labels{i}
        % in the current subject's channel array
        reorder = zeros(1, n_canonical);
        for i = 1:n_canonical
            idx = find(strcmp(current_labels, canonical_labels{i}));
            if isempty(idx)
                error('Subject %s [%s]: canonical label "%s" not found in ERP.chanlocs', ...
                    subjID, ext, canonical_labels{i});
            end
            reorder(i) = idx;
        end

        % Log the reordering
        moved = find(reorder ~= 1:n_canonical);
        fprintf('  [%s] reordering %d channel(s)\n', ext, length(moved));
        fprintf(fid_log, '  [%s] reordering %d channel(s): ', ext, length(moved));
        for m = moved
            fprintf(fid_log, '%s (%d→%d) ', canonical_labels{m}, reorder(m), m);
        end
        fprintf(fid_log, '\n');

        % Back up original
        copyfile(fpath, fpath_bk);

        % Apply reordering to bindata [nchan × pnts × nbin]
        ERP.bindata  = ERP.bindata(reorder,  :, :);
        ERP.binerror = ERP.binerror(reorder, :, :);
        ERP.chanlocs = ERP.chanlocs(reorder);
        ERP.nchan    = n_canonical;

        % Save corrected ERP (overwrites original)
        pop_savemyerp(ERP, ...
            'erpname',  ERP.erpname, ...
            'filename', fname, ...
            'filepath', subject_DIR, ...
            'warning',  'off');

        fprintf('  [%s] saved (backup: %s)\n', ext, fname_bk);
        n_fixed = n_fixed + 1;

        % Add to ALLERP
        CURRENTERP         = CURRENTERP + 1;
        ALLERP(CURRENTERP) = ERP;
    end

end  % subject loop

%% -------------------------------------------------------------------------
%  4. Summary
% -------------------------------------------------------------------------
fprintf('\n\n========== SUMMARY ==========\n');
fprintf('Files fixed:          %d\n', n_fixed);
fprintf('Already correct:      %d\n', n_already);
fprintf('Skipped (not found or mismatch): %d\n', n_skipped);
fprintf('Log written to: %s\n', log_fname);

fprintf(fid_log, '\n========== SUMMARY ==========\n');
fprintf(fid_log, 'Files fixed:          %d\n', n_fixed);
fprintf(fid_log, 'Already correct:      %d\n', n_already);
fprintf(fid_log, 'Skipped:              %d\n', n_skipped);
fclose(fid_log);

erplab redraw;

%% =========================================================================
%  VERIFICATION
%  After running, verify a few subjects to confirm the fix worked:
%
%  ERP = pop_loaderp('filename','S106_VSL2.erp','filepath',fullfile(pwd,'DATA','S106'));
%  {ERP.chanlocs.labels}
%
%  All subjects should now have identical channel order matching canonical_labels.
% =========================================================================
