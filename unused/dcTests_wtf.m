%title = "animalid group event"
Fs = 1000;
window = [-3, 3];
%% get average spectrogram
window_tbeg = window(1);
window_tend = window(2);
totalSpecs = size(ReinON_dataWindows,1);
timestamps = 0:1/Fs:size(ReinON_dataWindows, 2)/Fs;
timestamps = timestamps - median(timestamps); % to shift the middle to zero

lfp.samplingRate = Fs;
lfp.timestamps = timestamps(1:size(ReinON_dataWindows, 2));

for row = 1:totalSpecs
    lfp.data = ReinON_dataWindows(row,:)';

    wavespec = bz_WaveSpec(lfp);

    ps = abs(wavespec.data').^2;

   if row == 1
       sumps = ps;
   end
   if row > 1
       sumps = sumps+ps;
   end
   if row == totalSpecs
       meanps = sumps/totalSpecs;
   end
end
%%
f1 = figure;
a1 = axes;
p1 = imagesc(wavespec.timestamps, wavespec.freqs, meanps);
hold on
p2 = line([0 0], [0 1000], 'Color', 'w');
a1.YDir = 'normal';
% a1.YScale = 'log';
y1 = ylabel('Frequency (Hz)');
x1 = xlabel('Time (sec)');



%%