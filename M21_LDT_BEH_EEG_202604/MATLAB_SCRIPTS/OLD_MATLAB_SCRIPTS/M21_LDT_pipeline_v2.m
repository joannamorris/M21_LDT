%% =========================================================================
%  M21_LDT_pipeline_v2.m
%  Full EEG preprocessing pipeline: load .vhdr → filter → bad channels →
%  ICA → interpolate → epoch → artifact rejection → average
%
%  Starting point: studyID_subjID_taskID.vhdr  (raw BrainVision file)
%  Expected location: DATA/subjID/M21_subjID_LDT.vhdr
%
%  Outputs
%  -------
%    <studyID>_<taskID>_pipeline_log.txt     — per-subject processing log
%    <studyID>_<taskID>_ICA_log.csv          — ICA components removed per subject
%    <studyID>_<taskID>_removed_channels.txt — bad channels per subject
%    <studyID>_<taskID>_trial_counts.csv     — accepted trials per condition
%    <studyID>_<taskID>_summary_stats.txt    — means/ranges for Methods section
%
%  Requires: EEGLAB with ERPLAB plug-in, ICLabel plug-in
%  Tested with: EEGLAB 2024.x, ERPLAB 10.x
% =========================================================================

%% -------------------------------------------------------------------------
%  0. Housekeeping
% -------------------------------------------------------------------------
clear; clc;
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
ALLERP     = buildERPstruct([]);
CURRENTERP = 0;

%% -------------------------------------------------------------------------
%  1. Single dialog — collect all parameters up front
% -------------------------------------------------------------------------
prompt = { ...
    'StudyID (e.g. M21):', ...
    'TaskID (e.g. LDT):', ...
    'Data collection location (pc | hc):', ...
    'Subject list file (one ID per line):', ...
    'Bin descriptor file (BDF, full filename):', ...
    'Downsample to (Hz):', ...
    'Epoch window (ms), e.g.  -200 1000:', ...
    'Artifact-rejection threshold (µV), e.g.  100:', ...
    'Artifact-rejection window (ms), e.g.  -100 600:', ...
    'EEGLAB directory (folder containing sample_locs/):'};
dlgtitle = 'Pipeline parameters';
dims     = [1 72];
definput = { ...
    'M21', 'LDT', 'hc', 'm21_subjlist_all.txt', 'M21_LDT_BDF.txt', ...
    '200', '-200 1000', '100', '-100 600', '/Users/jmorris/Documents/MATLAB/eeglab2024.2'};
my_input = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(my_input)
    error('Pipeline cancelled by user.');
end

DIR      = pwd;
studyID  = strtrim(my_input{1});
taskID   = strtrim(my_input{2});
location = lower(strtrim(my_input{3}));
srate    = str2double(my_input{6});

epoch_vec  = str2num(my_input{7});  %#ok<ST2NM>
arj_thresh = str2double(my_input{8});
arj_win    = str2num(my_input{9});  %#ok<ST2NM>
eeglab_dir = strtrim(my_input{10});

if numel(epoch_vec) ~= 2 || numel(arj_win) ~= 2
    error('Epoch window and artifact window must each be two numbers.');
end
if isnan(srate) || srate <= 0
    error('Downsample rate must be a positive number.');
end

subj_list = importdata(strtrim(my_input{4}));
nsubj     = length(subj_list);
bdf_file  = fullfile(DIR, strtrim(my_input{5}));

if ~isfile(bdf_file)
    error('Bin descriptor file not found: %s', bdf_file);
end

%% Channel locations file — resolved from EEGLAB directory
chan_locs_file = fullfile(eeglab_dir, 'sample_locs', 'Standard-10-10-Cap33.ced');
if ~isfile(chan_locs_file)
    error(['Channel locations file not found: %s\n' ...
           'Check that your EEGLAB directory is correct and contains sample_locs/.'], ...
           chan_locs_file);
end

%% Location-dependent settings
if strcmp(location, 'hc')
    chan_num   = 32;
    reref_file = fullfile(DIR, 'reref_eq_brainvision_hampshire.txt');
else
    chan_num   = 31;   % 30 EEG + 1 ref at PC
    reref_file = fullfile(DIR, 'reref_eq_pchpl.txt');
end

if ~isfile(reref_file)
    error('Re-reference file not found: %s', reref_file);
end

%% Filename prefix used in every output file
if isempty(taskID)
    task_pfx = '';
else
    task_pfx = ['_' taskID];
end
study_tag = [studyID task_pfx];   % e.g. "M21_LDT"

%% -------------------------------------------------------------------------
%  2. Open output files
% -------------------------------------------------------------------------
log_fname   = fullfile(DIR, [study_tag '_pipeline_log.txt']);
chan_fname   = fullfile(DIR, [study_tag '_removed_channels.txt']);
trial_fname  = fullfile(DIR, [study_tag '_trial_counts.csv']);

fid_log   = fopen(log_fname,  'w');
fid_chan  = fopen(chan_fname,  'w');
fid_trial = fopen(trial_fname, 'w');

if any([fid_log fid_chan fid_trial] == -1)
    error('Could not open one or more output files for writing. Check folder permissions.');
end

fprintf(fid_log, 'Pipeline log — %s\n', study_tag);
fprintf(fid_log, 'Run: %s\n', datestr(now));
fprintf(fid_log, 'Location: %s   Channels: %d   Srate: %d Hz\n', ...
    location, chan_num, srate);
fprintf(fid_log, 'Epoch: [%d %d] ms   ARJ threshold: +/-%d uV   ARJ window: [%d %d] ms\n\n', ...
    epoch_vec(1), epoch_vec(2), arj_thresh, arj_win(1), arj_win(2));

fprintf(fid_chan, 'Bad-channel removal log — %s\n', study_tag);
fprintf(fid_chan, 'Run: %s\n\n', datestr(now));

%% -------------------------------------------------------------------------
%  3. Initialise accumulators
% -------------------------------------------------------------------------
ICA_log = table( ...
    strings(nsubj, 1), ...
    nan(nsubj, 1), ...
    strings(nsubj, 1), ...
    'VariableNames', {'Subject', 'N_Removed_ICs', 'Status'});

trial_header_written = false;
bin_labels           = {};
ica_removed_vec      = nan(nsubj, 1);
all_trial_counts     = [];

%% =========================================================================
%  MAIN SUBJECT LOOP
%
%  Suffix chain built up across stages:
%    (none) = loaded from subjID_taskID.set
%    _FLT   = band-pass filtered
%    _RSP   = resampled
%    _REF   = re-referenced
%    _ELS   = event list created
%    _BIN   = bins assigned
%    _CLN   = bad channels removed (automated)
%    _ICA   = ICA artefact components removed
%    _INT   = bad channels interpolated
%    _EPC   = epoched
%    _ARJ   = artifact-rejected epochs flagged
% =========================================================================

%% -------------------------------------------------------------------------
%  Pre-flight check: verify clean_rawdata helper functions are accessible.
%
%  clean_channels requires design_fir, design_kaiser, filtfilt_fast, and
%  filter_fast. In some EEGLAB installations these are missing from the
%  clean_rawdata2.x plugin and must be copied manually. Instructions:
%    1. Copy *.m from <old_eeglab>/plugins/clean_rawdata/private/
%       to <eeglab>/plugins/clean_rawdata2.11/
%    2. Copy design_fir.m from <eeglab>/plugins/Cleanline*/private/
%       to <eeglab>/plugins/clean_rawdata2.11/
%    3. Restart MATLAB and rerun.
% -------------------------------------------------------------------------
required_fns = {'design_fir', 'design_kaiser', 'filtfilt_fast', 'filter_fast'};
missing_fns  = {};
for fi = 1:length(required_fns)
    if isempty(which(required_fns{fi}))
        missing_fns{end+1} = required_fns{fi}; %#ok<AGROW>
    end
end
if ~isempty(missing_fns)
    fclose(fid_log); fclose(fid_chan); fclose(fid_trial);
    error(['Missing clean_rawdata dependencies: %s\n\n' ...
           'Copy the missing .m files to:\n  %s\n' ...
           'then restart MATLAB and rerun.'], ...
           strjoin(missing_fns, ', '), ...
           fullfile(eeglab_dir, 'plugins', 'clean_rawdata2.11'));
end
fprintf('Pre-flight check passed: all clean_rawdata dependencies found.\n');

for subject = 1:nsubj

    subjID      = strtrim(subj_list{subject});
    subject_DIR = fullfile(DIR, 'DATA', subjID);

    fprintf('\n\n==============================\n');
    fprintf('Subject %d / %d : %s\n', subject, nsubj, subjID);
    fprintf('==============================\n');
    fprintf(fid_log, '\n--- Subject %s ---\n', subjID);

    ICA_log.Subject(subject) = string(subjID);

    % ------------------------------------------------------------------
    %  STAGE 1: Check BrainVision source files and load .vhdr
    %  Expected filename: studyID_subjID_taskID.vhdr
    %  e.g. DATA/S101/M21_S101_LDT.vhdr
    % ------------------------------------------------------------------
    fname_base = [subjID task_pfx];                    % e.g. S101_LDT
    base_vhdr  = [studyID '_' subjID task_pfx '.vhdr'];
    base_vmrk  = [studyID '_' subjID task_pfx '.vmrk'];
    base_eeg   = [studyID '_' subjID task_pfx '.eeg'];

    src_ok = isfile(fullfile(subject_DIR, base_vhdr)) && ...
             isfile(fullfile(subject_DIR, base_vmrk)) && ...
             isfile(fullfile(subject_DIR, base_eeg));

    if ~src_ok
        fprintf(' *** Source files not found — skipping %s ***\n', subjID);
        fprintf(fid_log, '  SKIPPED — .vhdr/.vmrk/.eeg not found\n');
        ICA_log.Status(subject) = "skipped - source missing";
        continue
    end

    fprintf('\n-- Stage 1: Load vhdr --\n');
    EEG = pop_loadbv(subject_DIR, base_vhdr);
    EEG.setname = fname_base;
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');
    eeglab redraw;
    fprintf(fid_log, '  Stage 1 done: loaded %s, saved %s.set\n', base_vhdr, fname_base);

    % ------------------------------------------------------------------
    %  STAGE 2: Filter -> Resample -> Channel locations -> Re-reference
    %           -> Event list -> Bin list
    % ------------------------------------------------------------------
    fprintf('\n-- Stage 2: Filter / resample / ref / bins --\n');

    % Band-pass filter (0.1-30 Hz, 4th-order Butterworth, DC removed)
    EEG = pop_basicfilter(EEG, 1:chan_num, ...
        'Boundary', 'boundary', ...
        'Cutoff',   [0.1 30], ...
        'Design',   'butter', ...
        'Filter',   'bandpass', ...
        'Order',    4, ...
        'RemoveDC', 'on');
    EEG.setname = [fname_base '_FLT'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');

    % Downsample
    EEG = pop_resample(EEG, srate);
    EEG.setname = [fname_base '_FLT_RSP'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');

    % Channel locations — must be added before pop_clean_rawdata (Stage 3)
    % Uses Standard-10-10-Cap33.ced from the EEGLAB sample_locs directory
    EEG = pop_chanedit(EEG, 'lookup', chan_locs_file);
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');

    % Re-reference
    EEG = pop_eegchanoperator(EEG, reref_file, 'Saveas', 'off');
    EEG.setname = [fname_base '_FLT_RSP_REF'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');

    % Create event list
    EEG = pop_creabasiceventlist(EEG, ...
        'AlphanumericCleaning', 'on', ...
        'BoundaryNumeric',      {-99}, ...
        'BoundaryString',       {'boundary'}, ...
        'Eventlist', fullfile(subject_DIR, [fname_base '_ELS.txt']));
    EEG.setname = [fname_base '_FLT_RSP_REF_ELS'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');

    % Assign bins
    EEG = pop_binlister(EEG, ...
        'BDF',       bdf_file, ...
        'ExportEL',  fullfile(subject_DIR, [fname_base '_ELS_BIN.txt']), ...
        'IndexEL',   1, ...
        'SendEL2',   'EEG&Text', ...
        'UpdateEEG', 'on', ...
        'Voutput',   'EEG');
    EEG.setname = [fname_base '_FLT_RSP_REF_ELS_BIN'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');
    eeglab redraw;
    fprintf(fid_log, '  Stage 2 done: filter / resample / ref / bins\n');

    % ------------------------------------------------------------------
    %  STAGE 3: Automated bad-channel removal
    %
    %  clean_artifacts() decides whether to use the location-based or
    %  location-free channel criterion by checking whether ALL channels
    %  have valid xyz coordinates. Channels 28-32 (Mastoid R/L, HEOG R/L,
    %  VEOG L) have no coordinates in the .ced file, which forces the
    %  fallback to the broken location-free path.
    %
    %  Workaround: temporarily remove channels 28-32 from the EEG
    %  structure, run clean_artifacts on channels 1-27 only (all of which
    %  have valid locations), then restore the non-EEG channels afterward.
    %  No data are lost — the removed channels are held in a variable and
    %  spliced back in by index after cleaning.
    %
    %  BurstCriterion and WindowCriterion are off: no time segments removed.
    % ------------------------------------------------------------------
    fprintf('\n-- Stage 3: Automated bad-channel removal --\n');

    % Indices of channels without xyz coordinates
    unlocated_idx = 28:32;

    % Save the full channel info and data rows for non-EEG channels
    saved_chanlocs = EEG.chanlocs(unlocated_idx);
    saved_data     = EEG.data(unlocated_idx, :);

    % Temporarily remove unlocated channels so clean_artifacts sees a
    % fully-located dataset and uses the location-based criterion
    EEG_clean      = EEG;
    EEG_clean.data     = EEG.data(1:27, :);
    EEG_clean.chanlocs = EEG.chanlocs(1:27);
    EEG_clean.nbchan   = 27;

    EEG_clean = clean_artifacts(EEG_clean, ...
        'FlatlineCriterion',  15, ...
        'ChannelCriterion',   0.65, ...
        'LineNoiseCriterion', 7, ...
        'Highpass',           'off', ...
        'BurstCriterion',     'off', ...
        'WindowCriterion',    'off', ...
        'BurstRejection',     'off');

    % Reconstruct which of the original 27 EEG channels were removed.
    % After clean_artifacts removes channels, EEG_clean.chanlocs contains
    % only the survivors, so we compare surviving labels against the
    % original 27 to identify which were dropped.
    original_labels  = {EEG.chanlocs(1:27).labels};
    surviving_labels = {EEG_clean.chanlocs.labels};
    removed_mask_27  = ~ismember(original_labels, surviving_labels);  % 1x27 logical

    % Restore the non-EEG channels (28-32) to the cleaned EEG structure.
    EEG.data     = [EEG_clean.data;  saved_data];
    EEG.chanlocs = [EEG_clean.chanlocs, saved_chanlocs];
    EEG.nbchan   = size(EEG.data, 1);

    % Build a full 32-channel clean_channel_mask:
    %   channels 1-27: true if kept, false if removed
    %   channels 28-32: always true (non-EEG, never flagged)
    full_mask_27 = ~removed_mask_27;   % 1x27 logical, true = kept
    EEG.etc.clean_channel_mask = [full_mask_27, true(1, length(unlocated_idx))];

    % Carry over chaninfo.removedchans so interpolation (Stage 5) works
    if isfield(EEG_clean, 'chaninfo') && isfield(EEG_clean.chaninfo, 'removedchans')
        EEG.chaninfo.removedchans = EEG_clean.chaninfo.removedchans;
    end


    EEG.setname = [fname_base '_FLT_RSP_REF_ELS_BIN_CLN'];
    EEG = pop_saveset(EEG, ...
        'filename', [EEG.setname '.set'], ...
        'filepath', subject_DIR);
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, 'gui', 'off');

    % Log removed channels
    fprintf(fid_chan, 'Subject: %s\n', subjID);
    if isfield(EEG, 'etc') && isfield(EEG.etc, 'clean_channel_mask')
        bad_idx = find(~EEG.etc.clean_channel_mask);
        if isempty(bad_idx)
            fprintf(fid_chan, '  No channels removed.\n\n');
            fprintf(fid_log,  '  Stage 3: no channels removed\n');
        else
            has_rc = isfield(EEG, 'chaninfo') && ...
                     isfield(EEG.chaninfo, 'removedchans') && ...
                     isstruct(EEG.chaninfo.removedchans) && ...
                     ~isempty(EEG.chaninfo.removedchans);
            for ci = 1:length(bad_idx)
                if has_rc && ci <= length(EEG.chaninfo.removedchans)
                    lbl = EEG.chaninfo.removedchans(ci).labels;
                else
                    lbl = '(label unavailable)';
                end
                fprintf(fid_chan, '  Removed ch %d: %s\n', bad_idx(ci), lbl);
            end
            fprintf(fid_chan, '\n');
            fprintf(fid_log, '  Stage 3: removed %d channel(s)\n', length(bad_idx));
        end
    else
        fprintf(fid_chan, '  clean_channel_mask not found — inspect manually.\n\n');
        fprintf(fid_log,  '  Stage 3: clean_channel_mask unavailable\n');
    end
    eeglab redraw;

    % ------------------------------------------------------------------
    %  STAGE 4: ICA
    %  Decompose with runica (extended mode), classify with ICLabel,
    %  flag components: muscle >= 0.90, eye >= 0.90, line noise >= 0.90
    % ------------------------------------------------------------------
    fprintf('\n-- Stage 4: ICA --\n');

    EEG = pop_runica(EEG, ...
        'icatype',   'runica', ...
        'extended',  1, ...
        'rndreset',  'yes', ...
        'interrupt', 'on');

    EEG = pop_iclabel(EEG, 'default');

    EEG = pop_icflag(EEG, ...
        [NaN NaN; ...   % Brain       — keep all
         0.90  1; ...   % Muscle      — remove if p >= 0.90
         0.90  1; ...   % Eye         — remove if p >= 0.90
         NaN NaN; ...   % Heart       — keep
         0.90  1; ...   % Line noise  — remove if p >= 0.90
         NaN NaN; ...   % Channel noise
         NaN NaN]);     % Other

    rejected_ICs = find(EEG.reject.gcompreject);
    n_removed    = length(rejected_ICs);

    ICA_log.N_Removed_ICs(subject) = n_removed;
    ICA_log.Status(subject)        = "processed";
    ica_removed_vec(subject)       = n_removed;

    fprintf('  %d ICA component(s) removed\n', n_removed);
    if n_removed > 0
        ic_str = strjoin(arrayfun(@num2str, rejected_ICs, 'UniformOutput', false), ', ');
    else
        ic_str = 'none';
    end
    fprintf(fid_log, '  Stage 4: %d component(s) removed (%s)\n', n_removed, ic_str);

    EEG = pop_subcomp(EEG, rejected_ICs, 0);
    EEG.setname = [fname_base '_FLT_RSP_REF_ELS_BIN_CLN_ICA'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');
    eeglab redraw;

    % ------------------------------------------------------------------
    %  STAGE 5: Interpolate channels removed in Stage 3
    % ------------------------------------------------------------------
    fprintf('\n-- Stage 5: Interpolation --\n');

    if isfield(EEG, 'chaninfo') && ...
            isfield(EEG.chaninfo, 'removedchans') && ...
            isstruct(EEG.chaninfo.removedchans) && ...
            ~isempty(EEG.chaninfo.removedchans)

        n_interp = length(EEG.chaninfo.removedchans);
        fprintf('  Interpolating %d removed channel(s)\n', n_interp);
        fprintf(fid_log, '  Stage 5: interpolating %d channel(s)\n', n_interp);
        EEG = eeg_interp(EEG, EEG.chaninfo.removedchans, 'spherical');
    else
        fprintf('  No removed channels — skipping interpolation\n');
        fprintf(fid_log, '  Stage 5: no interpolation needed\n');
    end

    EEG.setname = [fname_base '_FLT_RSP_REF_ELS_BIN_CLN_ICA_INT'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');
    eeglab redraw;

    % ------------------------------------------------------------------
    %  STAGE 6: Epoch -> Artifact rejection -> Average
    % ------------------------------------------------------------------
    fprintf('\n-- Stage 6: Epoch / artifact rejection / average --\n');

    % Epoch (baseline correction applied to pre-stimulus window)
    EEG = pop_epochbin(EEG, epoch_vec, 'pre');
    EEG.setname = [fname_base '_FLT_RSP_REF_ELS_BIN_CLN_ICA_INT_EPC'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');
    eeglab redraw;

    % Artifact rejection — amplitude threshold on EEG channels only
    % Channel 1 = reference, chan_num = EOG; both excluded from flagging
    EEG = pop_artextval(EEG, ...
        'Channel',   2:(chan_num - 1), ...
        'Flag',      1, ...
        'LowPass',  -1, ...
        'Threshold', [-arj_thresh  arj_thresh], ...
        'Twindow',   arj_win);

    EEG.setname = [fname_base '_FLT_RSP_REF_ELS_BIN_CLN_ICA_INT_EPC_ARJ'];
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');

    % Artifact summary to text file
    EEG = pop_summary_AR_eeg_detection(EEG, ...
        fullfile(subject_DIR, [subjID task_pfx '_ARJ_SUM.txt']));
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET, ...
        'setname', EEG.setname, ...
        'save', fullfile(subject_DIR, [EEG.setname '.set']), ...
        'gui', 'off');
    eeglab redraw;

    % Average — good epochs only, include SEM
    ERP = pop_averager(EEG, ...
        'Criterion',       'good', ...
        'ExcludeBoundary', 'on', ...
        'SEM',             'on');

    ERP.erpname = [subjID task_pfx];
    pop_savemyerp(ERP, ...
        'erpname',  ERP.erpname, ...
        'filename', [ERP.erpname '.erp'], ...
        'filepath', subject_DIR, ...
        'warning',  'off');

    CURRENTERP         = CURRENTERP + 1;
    ALLERP(CURRENTERP) = ERP;
    eeglab redraw;
    erplab redraw;

    % ------------------------------------------------------------------
    %  Collect trial counts per bin
    % ------------------------------------------------------------------
    if isfield(ERP, 'ntrials') && isfield(ERP.ntrials, 'accepted')
        counts = ERP.ntrials.accepted;   % 1 x nBins

        % Accumulate for summary statistics
        if isempty(all_trial_counts)
            all_trial_counts = counts;
        else
            all_trial_counts = [all_trial_counts; counts]; %#ok<AGROW>
        end

        % Write CSV header from first valid subject's bin descriptions
        if ~trial_header_written
            if isfield(ERP, 'bindescr') && ~isempty(ERP.bindescr)
                bin_labels = ERP.bindescr;
            else
                bin_labels = arrayfun(@(b) sprintf('Bin%d', b), ...
                    1:length(counts), 'UniformOutput', false);
            end
            fprintf(fid_trial, 'Subject');
            fprintf(fid_trial, ',%s', bin_labels{:});
            fprintf(fid_trial, '\n');
            trial_header_written = true;
        end

        fprintf(fid_trial, '%s', subjID);
        fprintf(fid_trial, ',%d', counts);
        fprintf(fid_trial, '\n');

        fprintf(fid_log, '  Stage 6: accepted trials per bin: %s\n', num2str(counts));
    else
        fprintf(fid_log, '  Stage 6: ntrials.accepted not available\n');
    end

    fprintf(fid_log, '  COMPLETED\n');

end  % subject loop

%% =========================================================================
%  Post-loop: write ICA log and summary statistics
% =========================================================================

%% ICA log CSV
ica_log_fname = fullfile(DIR, [study_tag '_ICA_log.csv']);
writetable(ICA_log, ica_log_fname);
fprintf('\nICA log saved: %s\n', ica_log_fname);

%% Summary statistics (for the Methods section)
sum_fname = fullfile(DIR, [study_tag '_summary_stats.txt']);
fid_sum   = fopen(sum_fname, 'w');

fprintf(fid_sum, 'Summary statistics for Methods section\n');
fprintf(fid_sum, 'Study: %s   Task: %s\n', studyID, taskID);
fprintf(fid_sum, 'Run: %s\n\n', datestr(now));

% ICA
valid_ica = ica_removed_vec(~isnan(ica_removed_vec));
if ~isempty(valid_ica)
    fprintf(fid_sum, '--- ICA components removed ---\n');
    fprintf(fid_sum, '  N subjects: %d\n',    length(valid_ica));
    fprintf(fid_sum, '  Mean:  %.1f\n',        mean(valid_ica));
    fprintf(fid_sum, '  SD:    %.1f\n',        std(valid_ica));
    fprintf(fid_sum, '  Range: %d - %d\n\n',  min(valid_ica), max(valid_ica));
    fprintf('\nICA components removed: M = %.1f, SD = %.1f, range %d-%d\n', ...
        mean(valid_ica), std(valid_ica), min(valid_ica), max(valid_ica));
end

% Trial counts per bin
if ~isempty(all_trial_counts)
    fprintf(fid_sum, '--- Accepted trials per condition ---\n');
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

fclose(fid_sum);

%% Close all open output files
fclose(fid_log);
fclose(fid_chan);
fclose(fid_trial);

fprintf('\n\nAll output files written to: %s\n', DIR);
fprintf('  %s\n', log_fname);
fprintf('  %s\n', chan_fname);
fprintf('  %s\n', trial_fname);
fprintf('  %s\n', ica_log_fname);
fprintf('  %s\n', sum_fname);
fprintf('\nPipeline complete.\n');

%% =========================================================================
%  Run these separately after reviewing individual ERPs:
%    M21_LDT_grand_average.m
%    M21_LDT_measure_amp.m
% =========================================================================
