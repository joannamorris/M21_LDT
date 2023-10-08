%% Clear memory and the command window
clear;
clc;

%% Load eeglab
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
ALLERP = buildERPstruct([]);

%% Set up variables holding key values 

%  Dialog box to get info about script variables 
prompt   = {'Enter StudyID:',...
            'Enter TaskID:',...
            'Enter name of subject list file:',...
            'Enter the part of the file names that comes after the subject and task IDs, including the underscores. If there are no filename extensions, leave the box empty:'};
dlgtitle =  'Input';
dims     = [1 70];
definput = {'M21','LDT','subjlist.txt','_FLT_RSP_REF_ELS_BIN'};
my_input   = inputdlg(prompt,dlgtitle,dims,definput);

    
DIR            = pwd;                         % Current folder (where the script should be located)
studyID        = my_input{1};                 % which study
task           = my_input{2};                 % which task
subj_list      = importdata(my_input{3});     % list of subject ids
f_string       = my_input{4};                 % this string allows you to specify which .set file to load
nsubj          = length(subj_list);           % number of subjects
  
%% Load the  ERPsets and make them available in the ERPLAB GUI

for subject = 1:nsubj
    subjID = subj_list{subject};
    fprintf('\n******\nProcessing subject %s\n******\n\n', subjID);
    
    subject_DIR = [DIR filesep subjID];
    fname       = [subjID '_' task f_string];    
    fname_set   = [fname '.set'];
    fname_fdt   = [fname '.fdt'];
    
    %% Check to make sure the dataset file exists
    if (exist([subject_DIR filesep fname_set ], 'file')<=0||...
            exist([subject_DIR filesep fname_fdt ], 'file')<=0);
        fprintf('\n *** WARNING: %s does not exist *** \n', fname);
        fprintf('\n *** Skip all processing for this subject *** \n\n');
    else 
        %% Load .set file
        fprintf('\n\n\n**** %s: Loading set file ****\n\n\n', fname_set);
        EEG = pop_loadset(fname_set, subject_DIR);
        EEG.setname = fname;
        EEG.datfile = fname_fdt; 
        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET,...
                                               'setname',EEG.setname,...
                                               'gui','off');
        eeglab redraw;

        %% Epoch
            % Extracts bin-based epochs (200 ms pre-stim, 800 ms post-stim.
            % Baseline correction by pre-stim window)
            
            fprintf('\n\n\n**** %s: Bin-based epoching ****\n\n\n', fname_set);

            EEG         = pop_epochbin( EEG , [-200.0  800.0],  'pre');
            EEG.setname = [fname '_EPC'];
            [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET,...
                                                 'setname',EEG.setname,...
                                                 'save', [subject_DIR filesep EEG.setname '.set'],...
                                                 'gui','off');
        eeglab redraw;

        %% Artifact Detection
        EEG  = pop_artextval( EEG ,...
                              'Channel',[ 1 31], ...
                              'Flag',  1,...
                              'LowPass',  -1,...
                              'Threshold', [ -100 100],...
                              'Twindow',[ -200 700] );
        EEG.setname = [fname '_EPC_ARJ'];
        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, CURRENTSET,...
                                                 'setname',EEG.setname,...
                                                 'save', [subject_DIR filesep EEG.setname '.set'],...
                                                 'gui','off');
        EEG = pop_summary_AR_eeg_detection(EEG, [subject_DIR filesep subjID '_' task  '_ARJ_SUM.txt']);

        eeglab redraw;

        %%  %% Report percentage of rejected trials (collapsed across all bins)
            artifact_proportion = getardetection(EEG);

        %%  %% Average
            % Only good trials.  Include standard deviation.  Save to disk.            
            
            fprintf('\n\n\n**** %s: Averaging ****\n\n\n', fname_set);

            ERP         = pop_averager( EEG, ...
                                       'Criterion'      , 'good', ...
                                       'ExcludeBoundary', 'on', ...
                                       'SEM'            , 'on');
            ERP.erpname = subjID;  % name for erpset menu
            pop_savemyerp(ERP,... 
                           'erpname', ERP.erpname,...
                           'filename', [ERP.erpname '.erp'],...
                           'filepath', subject_DIR, ...
                           'warning', 'off');

           
            CURRENTERP         = CURRENTERP + 1;
            ALLERP(CURRENTERP) = ERP;
            
            eeglab redraw;
            erplab redraw;

    end % end of the "if/else" statement that makes sure the file exists

end % end of looping through all subjects
