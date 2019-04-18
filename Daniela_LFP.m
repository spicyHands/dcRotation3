tic %counts time to run script
selpath = uigetdir('F:\Daniela');
listing = dir(selpath);
Nex5Files = listing(3:end);
cd(Nex5Files.folder)
%% Load each mouse's recordings
for file = 1:length(Nex5Files) % Load .nex5 file (e.g. a mouse's recordings for that day)
    
    nex5FileData = readNex5File(Nex5Files(file).name); % This is the entire .nex5 dataset
    Session.Name = Nex5Files(file).name(1:end-5); % This is the filename
    status = ['Starting  ' Session.Name]; % Indicates what file you're working with
    % what's status for????
    
    
    %% Event timestamp extraction
    LP_OFF = nex5FileData.events{1}.timestamps;
    LP_ON = nex5FileData.events{2}.timestamps;
    REIN_OFF = nex5FileData.events{3}.timestamps;
    REIN_ON = nex5FileData.events{4}.timestamps;
    SESS_OFF = max(nex5FileData.events{5}.timestamps); %Session end timestamp
    SESS_ON = min(nex5FileData.events{6}.timestamps); %Session start timestamp
    
    % Removes Lever Press Onset and Offsets Occuring Outside of Session Start
    % (t = "true" press)
    t_LP_OFF = LP_OFF(LP_OFF > SESS_ON);
    t_LP_OFF = t_LP_OFF(t_LP_OFF < SESS_OFF);
    %t_LP_OFF = t_LP_OFF(2:end);
    t_LP_ON = LP_ON(LP_ON > SESS_ON);
    t_LP_ON = t_LP_ON(t_LP_ON < SESS_OFF);
    t_LP_ON = t_LP_ON(1:end-1);
    % Remove lever press onset and offset that don't follow each other
    %(e.g. Offsets occuring before Onsets)
    if ~(length(t_LP_OFF) == length(t_LP_ON))
        if length(t_LP_OFF) > length(t_LP_ON)
            t_LP_OFF = t_LP_OFF(1:end-2);
        end
        if length(t_LP_OFF) < length(t_LP_ON)
            t_LP_ON = t_LP_ON(1:end-1);
        end
    end
    %Get Lever Press Lengths by subtraction and remove LPs with <100 ms IPI
    LP_Length = t_LP_OFF - t_LP_ON;
    t_LP_ON = t_LP_ON(LP_Length > .1);
    t_LP_OFF = t_LP_OFF(LP_Length > .1);
    LP_Length = t_LP_OFF - t_LP_ON;
    
    
    %% Append data to Session data structure for analysis
    Session.Events.SessionStart = SESS_ON; 
    Session.Events.SessionEnd = SESS_OFF;
    Session.Events.ReinON.ts = REIN_ON; % timestamps of Reinforcer delivery Onset
    Session.Events.ReinON.Event_Label = 'Reinforcement Onset';
    Session.Events.ReinOFF.ts = REIN_OFF; % timestamps of Reinforcer delivery Offset
    Session.Events.ReinOFF.Event_Label = 'Reinforcement Offset';
    Session.Events.LPOFF.ts = t_LP_OFF; % timestamps of LP Offset
    Session.Events.LPOFF.Event_Label = 'Lever Press Offset';
    Session.Events.LPON.ts = t_LP_ON; % timestamps of LP Onset
    Session.Events.LPON.Event_Label = 'Lever Press Onset';
    Session.Events.LeverPress_Durations = LP_Length;
    Session.Events.TotalReinforcersEarned = length(REIN_ON);
    Session.base_time_start = -5; % start time for baseline and data window (seconds)
    Session.base_time_end = -2; % end time for baseline window (seconds)
    Session.post_event_time = 5; % end time for data window (seconds)
    
    
    %% LFP Channel Processing
    Fs = nex5FileData.freq; % Sampling frequency (Hz)
    timeStep = 1/Fs;
    tbeg = nex5FileData.tbeg;
    tend = nex5FileData.tend;
    %addToEndTime = timeStep*(tend-tbeg);
    LFP_timestamps = tbeg:timeStep:tend;
    time_window = Session.base_time_start:1/Fs:Session.post_event_time;
    for channel = 12%:length(nex5FileData.contvars) % for each LFP channel (skip the ADC and AUX channels)
        
        LFP_Data = nex5FileData.contvars{channel}.data; %extracts channel LFP
        
        %% Notch Filter
        wo = 60/(Fs/2);
        bw = wo/35;
        [num,den]=iirnotch(wo,bw); % notch filter implementation 
        notched_LFP_Data = filter(num,den,LFP_Data);
        
        %% Bandpass filter
        [b, a] = butter(2, [.5 250]/(Fs/2)); % Create butterworth Filter (.5 - 250 Hz)
        buttered_LFP_Data = filter(b, a, notched_LFP_Data); % butterworth filtered data
        
        %% downsample
        downsampled_LFP_Data = decimate(buttered_LFP_Data, 120, 'fir');
        
        %% test plots, remove later
        TEST_Fs = 30*1000;
        TEST_downFs = 250;
        TEST_endTime = 1; %sec

        %don't change:
        TEST_timeStep = 1/Fs;
        TEST_timeVector = 0:TEST_timeStep:TEST_endTime;
        TEST_yStop = (TEST_endTime*TEST_Fs) + 1 ;        
        TEST_downTimeStep = 1/TEST_downFs;
        TEST_downTimeVector = 0:TEST_downTimeStep:TEST_endTime;
        TEST_downYStop = (TEST_endTime*TEST_downFs) +1;

        plot(TEST_timeVector, LFP_Data(1:TEST_yStop))
        hold on
        plot(TEST_timeVector, notched_LFP_Data(1:TEST_yStop))
        hold on
        plot(TEST_timeVector, buttered_LFP_Data(1:TEST_yStop))
        hold on
        plot(TEST_downTimeVector, downsampled_LFP_Data(1:TEST_downYStop))
            
        %% Create Peri-event data windows (in this case, lever press onset)
        for event_index = 1:3%length(Session.Events.LPON.ts)
        
            Closest_event_idx = nearestpoint(Session.Events.LPON.ts(event_index),LFP_timestamps); %find nearest data timestamp to lever press onset timestamp
            data_window = buttered_LFP_Data(Closest_event_idx + Session.base_time_start * Fs : Closest_event_idx + Session.post_event_time * Fs)'; % create peri-event data window
            %% Bandpass Filter
            filter_range = [4 10]; % Bandpass filter range (e.g. theta 4-10 Hz)
            theta_filtered = eegfilt(data_window,Fs,filter_range(1),filter_range(2)); %Filter in the theta range
            theta_power = abs(hilbert(eegfilt(data_window,Fs,filter_range(1),filter_range(2))')').^2; %Calculate theta power
            
            %% stuff for all the bandpass stuffs
            
%            freq_cell = {[1 4], [4 8] , [8 12], [12 30] , [30 50]}
%             for i = 1:length(freq_cell) % for each band
%                 low = freq_cell{i}(1) % this is low
%                 high = freq_cell{i}(2) % this is high
%                 filtered_data = filter(low, high, 'adjasdj')%rthis is you filtering it based on that
%                 if i == 1
%                     frequency_filtered.delta.filtered_data = filtered_data;
%                 elseif i == 2
%                     frequency_filtered.theta.filtered_data = filtered_data;
%                 end  
%             end

            
            %% Store data per event
            Session.Events.LPON.data_window{event_index} = data_window;
            Session.Events.LPON.theta_filtered{event_index} = theta_filtered;
            Session.Events.LPON.theta_power{event_index} = theta_power;
        end
        
    end
    % Save session
    %save(Session.Name, 'Session', '-v7.3');

end
toc %counts time to run script

% Sumperipose filtered over raw
figure
hold on
% Plot raw
subplot(3,1,1)
plot(time_window, data_window)
xlabel('Time (ms)')
ylabel('Voltage (mV)')
title('Raw')
% Plot Theta Filtered
subplot(3,1,2)
plot(time_window, theta_filtered)
xlabel('Time (ms)')
ylabel('Voltage (mV)')
title('Theta Filtered')
% Plot Theta Power
subplot(3,1,3)
plot(time_window, log(theta_power));
xlabel('Time (ms)')
ylabel('Theta Power (log)')
title('Theta Power')
hold off
