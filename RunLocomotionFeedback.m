%RunLocomotionFeedback

%% suppress m-lint warnings
%#ok<*MCCD,*NASGU,*ASGLU,*CTCH>
clearvars -except sStimPresets sStimParamsSettings sExpMeta;

%% set default variables and debug switches
intStimSet = 1;
boolUseSGL = false;
boolUseNI = false;
boolDebug = true;

%% set channel ids
%niCh0=onset
%niCh1=running
%niCh2=sync
intStimOnsetChanNI=0;
intRunningChanNI=2;
intStreamNI = -1;

%% retrieve RunExperiment variables
fprintf('Starting %s [%s]\n',mfilename,getTime);
if exist('sExpMeta','var')
	%defaults
	dblPupilLightMultiplier = 1; %strength of infrared LEDs
	dblSyncLightMultiplier = 0.3;
	strHostAddress = '192.87.10.238'; %default host address
	objDaqOut = [];
	
	%expand structure
	if isfield(sExpMeta,'dblPupilLightMultiplier'),dblPupilLightMultiplier=sExpMeta.dblPupilLightMultiplier;end
	if isfield(sExpMeta,'dblSyncLightMultiplier'),dblSyncLightMultiplier=sExpMeta.dblSyncLightMultiplier;end
	if isfield(sExpMeta,'strHostAddress'),strHostAddress=sExpMeta.strHostAddress;end
	if isfield(sExpMeta,'objDaqOut'),objDaqOut=sExpMeta.objDaqOut;end
	if isfield(sExpMeta,'boolUseSGL'),boolUseSGL=sExpMeta.boolUseSGL;end
	if isfield(sExpMeta,'boolUseNI'),boolUseNI=sExpMeta.boolUseNI;end
else
	sExpMeta = [];
end

%% query user input for recording name
if exist('sStimParamsSettings','var') && isfield(sStimParamsSettings,'strRecording')
	strRecording = sStimParamsSettings.strRecording;
else
	strRecording = input('Recording name (e.g., MouseX): ', 's');
end


%% input params
fprintf('Loading settings...\n');
if ~exist('sStimParamsSettings','var') || isempty(sStimParamsSettings) || ~(strcmpi(sStimParamsSettings.strStimType,'SquareGrating') || ~strcmpi(sStimParamsSettings.strStimType,'SineGrating'))
	%general
	sStimParamsSettings = struct;
	sStimParamsSettings.strStimType = 'Flyover';
	sStimParamsSettings.strOutputPath = 'C:\_Data\Exp'; %appends date
	sStimParamsSettings.strTempObjectPath = 'C:\_Data\TempObjects\';%'X:\JorritMontijn\';%X:\JorritMontijn\ or F:\Data\Temp\
	
	%visual space parameters
	sStimParamsSettings.dblSubjectPosX_cm = 0; % cm; relative to center of screen
	sStimParamsSettings.dblSubjectPosY_cm = -2.5; % cm; relative to center of screen, -3.5
	sStimParamsSettings.dblScreenDistance_cm = 17; % cm; measured, 14
	sStimParamsSettings.vecUseMask = 0; %[1] if mask to emulate retinal-space, [0] use screen-space
	
	%screen variables
	sStimParamsSettings.intCornerTrigger = 2; % integer switch; 0=none,1=upper left, 2=upper right, 3=lower left, 4=lower right
	sStimParamsSettings.dblCornerSize = 1/30; % fraction of screen width
	sStimParamsSettings.dblScreenWidth_cm = 51; % cm; measured [51]
	sStimParamsSettings.dblScreenHeight_cm = 29; % cm; measured [29]
	sStimParamsSettings.dblScreenWidth_deg = 2 * atand(sStimParamsSettings.dblScreenWidth_cm / (2 * sStimParamsSettings.dblScreenDistance_cm));
	sStimParamsSettings.dblScreenHeight_deg = 2 * atand(sStimParamsSettings.dblScreenHeight_cm / (2 * sStimParamsSettings.dblScreenDistance_cm));
	sStimParamsSettings.intUseScreen = 2; %which screen to use
	sStimParamsSettings.dblBackground = 0.5; %background intensity (dbl, [0 1])
	sStimParamsSettings.intBackground = round(mean(sStimParamsSettings.dblBackground)*255);
	
	%stimulus control variables
	sStimParamsSettings.intUseDaqDevice = 1; %ID of DAQ device
	sStimParamsSettings.intUseParPool = 2; %number of workers in parallel pool; [2]
	sStimParamsSettings.intUseGPU = 1;
else
	% evaluate and assign pre-defined values to structure
	cellFields = fieldnames(sStimParamsSettings);
	for intField=1:numel(cellFields)
		try
			sStimParamsSettings.(cellFields{intField}) = eval(sStimParamsSettings.(cellFields{intField}));
		catch
			sStimParamsSettings.(cellFields{intField}) = sStimParamsSettings.(cellFields{intField});
		end
	end
end
if boolDebug == 1
	intUseScreen = 0;
else
	intUseScreen = sStimParamsSettings.intUseScreen;
end


%% set output locations for logs
strOutputPath = sStimParamsSettings.strOutputPath;
strTempObjectPath = sStimParamsSettings.strTempObjectPath;
strThisFilePath = mfilename('fullpath');
[strFilename,strLogDir,strTempDir,strTexDir] = RE_assertPaths(strOutputPath,strRecording,strTempObjectPath,strThisFilePath);
fprintf('Saving output in directory %s\n',strLogDir);

%% initialize connection with SpikeGLX
if boolUseSGL
	%check if data are supplied
	if exist('sExpMeta','var') && isfield(sExpMeta,'hSGL') && isfield(sExpMeta,'strRunName') && isfield(sExpMeta,'sParamsSGL')
		%get data
		hSGL = sExpMeta.hSGL;
		strRunName = sExpMeta.strRunName;
		sParamsSGL = sExpMeta.sParamsSGL;
		
		%start recording
		intOutFlag = StartRecordingSGL(hSGL);
	else
		%start connection
		fprintf('Opening SpikeGLX connection & starting recording "%s" [%s]...\n',strRecording,getTime);
		[hSGL,strRunName,sParamsSGL] = InitSGL(strRecording,strHostAddress);
	end
	fprintf('SGL saving to "%s", matlab saving to "%s.mat" [%s]...\n',strRunName,strFilename,getTime);
	
	%% check disk space available
	strDataDirSGL = GetDataDir(hSGL);
	jFileObj = java.io.File(strDataDirSGL);
	dblFreeGB = (jFileObj.getFreeSpace)/(1024^3);
	if dblFreeGB < 100,warning([mfilename ':LowDiskSpace'],'Low disk space available (%.0fGB) for Neuropixels data (dir: %s)',dblFreeGB,strDataDirSGL);end
	
	%% prepare real-time stream
	%retrieve some parameters
	dblSampFreqNI = GetSampleRate(hSGL, intStreamNI);
	dblNI2V = (sParamsSGL.niAiRangeMax) / (double(intmax('int16'))/2);
	
	%assign data
	sStream = SC_populateStreamCoreStructure([]);
	sStream.NI2V = dblNI2V;
	sStream.intStreamNI = intStreamNI;
	sStream.intStimOnsetChanNI=intStimOnsetChanNI;
	sStream.intRunningChanNI=intRunningChanNI;
	sStream.dblSampFreqNI=dblSampFreqNI;
	sStream.hSGL = hSGL;
else
	hSGL = [];
	sParamsSGL = struct;
end

%% initialize parallel pool && gpu
if sStimParamsSettings.intUseParPool > 0 && isempty(gcp('nocreate'))
	parpool(sStimParamsSettings.intUseParPool * [1 1]);
end
if sStimParamsSettings.intUseGPU > 0
	objGPU = gpuDevice(sStimParamsSettings.intUseGPU);
end
if isempty(gcp('nocreate')) || (gcp('nocreate').NumWorkers < 2)
	error([mfilename ':ParallelFail'],'This function requires at least two active workers in the parallel pool');
end

%% initialize NI I/O box
if boolUseNI
	%initialize
	fprintf('Connecting to National Instruments box...\n');
	boolDaqOutRunning = false;
	if exist('objDaqOut','var') && ~isempty(objDaqOut)
		try
			%turns leds on
			stop(objDaqOut);
			outputData1 = dblSyncLightMultiplier*cat(1,linspace(3, 3, 200)',linspace(0, 0, 50)');
			outputData2 = dblPupilLightMultiplier*linspace(3, 3, 250)';
			queueOutputData(objDaqOut,[outputData1 outputData2]);
			prepare(objDaqOut);
			pause(0.1);
			startBackground(objDaqOut)
			boolDaqOutRunning = true;
		catch
		end
	end
	if ~boolDaqOutRunning
		objDaqOut = openDaqOutput(sStimParamsSettings.intUseDaqDevice);
		%turns leds on
		stop(objDaqOut);
		outputData1 = dblSyncLightMultiplier*cat(1,linspace(3, 3, 200)',linspace(0, 0, 50)');
		outputData2 = dblPupilLightMultiplier*linspace(3, 3, 250)';
		queueOutputData(objDaqOut,[outputData1 outputData2]);
		prepare(objDaqOut);
		pause(0.1);
		startBackground(objDaqOut)
	end
end

%% open screen & start experiment
try
	%% INITALIZE SCREEN
	fprintf('Starting PsychToolBox extension...\n');
	%open window
	AssertOpenGL;
	KbName('UnifyKeyNames');
	intOldVerbosity = Screen('Preference', 'Verbosity',1); %stop PTB spamming
	if boolDebug == 1, vecInitRect = [0 0 640 640];else vecInitRect = [];end
	try
		Screen('Preference', 'SkipSyncTests', 0);
		[ptrWindow,vecRect] = Screen('OpenWindow', intUseScreen,sStimParamsSettings.intBackground,vecInitRect);
	catch ME
		warning([mfilename ':ErrorPTB'],'Psychtoolbox error, attempting with sync test skip [msg: %s]',ME.message);
		Screen('Preference', 'SkipSyncTests', 1);
		[ptrWindow,vecRect] = Screen('OpenWindow', intUseScreen,sStimParamsSettings.intBackground,vecInitRect);
	end
	%window variables
	sStimParamsSettings.ptrWindow = ptrWindow;
	sStimParamsSettings.vecRect = vecRect;
	sStimParamsSettings.intScreenWidth_pix = vecRect(3)-vecRect(1);
	sStimParamsSettings.intScreenHeight_pix = vecRect(4)-vecRect(2);
	
	%% MAXIMIZE PRIORITY
	intOldPriority = 0;
	if boolDebug == 0
		intPriorityLevel=MaxPriority(ptrWindow);
		intOldPriority = Priority(intPriorityLevel);
	end
	
	%% get refresh rate
	dblStimFrameRate=Screen('FrameRate', ptrWindow);
	intStimFrameRate = round(dblStimFrameRate);
	dblStimFrameDur = mean(1/dblStimFrameRate);
	dblInterFlipInterval = Screen('GetFlipInterval', ptrWindow);
	if dblStimFrameDur/dblInterFlipInterval > 1.05 || dblStimFrameDur/dblInterFlipInterval < 0.95
		warning([mfilename ':InconsistentFlipDur'],sprintf('Something iffy with flip speed and monitor refresh rate detected; frame duration is %fs, while flip interval is %fs!',dblStimFrameDur,dblInterFlipInterval));
	end
	
	%% pre-allocate & set parameters
	%parameters
	dblStimDur = 1; %you will have to change this to however long one stimulus takes
	dblRunThreshold = 1;
	%fixed stufff
	cellAsyncObjects = [];
	intStimNumber = 0;
	dblDaqRefillDur = 0.5; %must be less than the stimulus duration, and cannot be less than ~300ms
	boolMustRefillDaq = false;
	if boolUseNI
		%refill daq
		stop(objDaqOut);
		outputData1 = dblSyncLightMultiplier*cat(1,linspace(3, 3, 200)',linspace(0, 0, 50)');
		outputData2 = dblPupilLightMultiplier*linspace(3, 3, 250)';
		queueOutputData(objDaqOut,[outputData1 outputData2]);
		prepare(objDaqOut);
	end
	
	%% run until escape button is pressed
	hTic = tic;
	dblLastStim = -inf;
	while ~CheckEsc()
		%read running speed
		if boolUseSGL
			[vecSamples,vecRunningData,vecSyncData,sStream]=readRunningSpeed(sStream,intRunningChanNI,intStimOnsetChanNI);
			sRunSpeed = PP_GetRunSpeed(vecRunningData,dblSampFreqNI);
			vecTimestamps_s = sRunSpeed.vecOutT + sStream.dblEphysTimeNI;
			vecTraversed_m = sRunSpeed.vecTraversed_m;
			vecRunningSpeed_mps = sRunSpeed.vecSpeed_mps; %this is filtered, so it might not be accurate for short data vectors
		else
			vecTimestamps_s = toc(hTic);
			vecRunningSpeed_mps = 2;
		end
		
		%do some sort of calculation here to determine whether the mouse crossed the threshold
		dblRunSpeed = max(vecRunningSpeed_mps);
		boolRunningThresholdCrossed = (dblRunSpeed > dblRunThreshold);
		intStimType = 2; %in case you want to present multiple stimuli, you can change this somewhere and it will be passed to PresentFlyOver.m
		
		%check if we should refill the DAQ
		if boolUseNI && boolMustRefillDaq && (toc(hTic) > (dblDaqRefillDur + dblLastStim))
			stop(objDaqOut);
			outputData1 = dblSyncLightMultiplier*cat(1,linspace(3, 3, 200)',linspace(0, 0, 50)');
			outputData2 = dblPupilLightMultiplier*linspace(3, 3, 250)';
			queueOutputData(objDaqOut,[outputData1 outputData2]);
			prepare(objDaqOut);
			boolMustRefillDaq = false;
		end
		
		%check if running speed is high enough
		if boolRunningThresholdCrossed && (toc(hTic) > (dblStimDur + dblLastStim))
			%% increment trial & log NI timestamp
			intStimNumber = intStimNumber + 1;
			dblLastStim = toc(hTic);
			fprintf('Stim %d started at %s (run speed was %.3f)\n',intStimNumber,getTime,dblRunSpeed);
			
			%% flash eye-tracker synchronization LED
			if boolUseNI
				startBackground(objDaqOut);
				boolMustRefillDaq = true;
			end
			
			%% start stimulus
			cellAsyncObjects{intStimNumber} = parfeval(@PresentFlyOver,2,hSGL,ptrWindow,intStimNumber,intStimType,sStimParamsSettings);
			
			%% get approximate timestamp for start
			if ~isempty(hSGL)
				dblApproxStimOnNI = GetScanCount(hSGL, intStreamNI)/dblSampFreqNI;
			else
				dblApproxStimOnNI = toc(hTic);
			end
			
			%% save temporary object for online analyses
			try
				%add timestamps
				sThisStimObject = struct;
				sThisStimObject.StimType = sStimParamsSettings.strStimType;
				sThisStimObject.dblStimOnNI = dblApproxStimOnNI;
				sThisStimObject.dblStimOffNI = dblApproxStimOnNI+dblStimDur;
				
				%save object
				sObject = sThisStimObject;
				save(fullfile(strTempDir,['Object',num2str(intStimNumber),'.mat']),'sObject');
			catch ME
				warning(ME.identifier,'%s',ME.message);
			end
		end
	end
	
	%% read async object timestamps
	structEP.TrialNumber = [];
	structEP.ActStimType = [];
	structEP.ActOnNI = [];
	structEP.ActOffNI = [];
	for intStimIdx=1:intStimNumber
		%retrieve data
		[dblStimOnNI,dblStimOffNI] = fetchOutputs(cellAsyncObjects{intStimIdx});
		
		% save stim-based data
		structEP.TrialNumber(intStimIdx) = intStimIdx;
		structEP.ActStimType(intStimIdx) = intStimType;
		structEP.ActOnNI(intStimIdx) = dblStimOnNI;
		structEP.ActOffNI(intStimIdx) = dblStimOffNI;
	end
	
	%% save data
	%save data
	structEP.sStimParams = sStimParamsSettings;
	save(fullfile(strLogDir,strFilename), 'structEP','sParamsSGL');
	
	%clean up
	fprintf('\nExperiment is finished at [%s], closing down and cleaning up...\n',getTime);
	
	%% close Daq IO
	if boolUseNI && ~(exist('sExpMeta','var') && isfield(sExpMeta,'objDaqOut'))
		try
			closeDaqOutput(objDaqOut);
		catch
		end
	end
	
	%% close screen
	Screen('Close',ptrWindow);
	Screen('CloseAll');
	ShowCursor;
	Priority(0);
	Screen('Preference', 'Verbosity',intOldVerbosity);
	
catch ME
	%% catch me and throw me
	fprintf('\n\n\nError occurred! Trying to save data and clean up...\n\n\n');
	
	%save data
	structEP.sStimParams = sStimParamsSettings;
	if ~exist('sParamsSGL','var'),sParamsSGL=[];end
	save(fullfile(strLogDir,strFilename), 'structEP','sParamsSGL');
	
	%% catch me and throw me
	Screen('Close');
	Screen('CloseAll');
	ShowCursor;
	Priority(0);
	Screen('Preference', 'Verbosity',intOldVerbosity);
	
	%% close Daq IO
	if boolUseNI && ~(exist('sExpMeta','var') && isfield(sExpMeta,'objDaqOut'))
		try
			closeDaqOutput(objDaqOut);
		catch
		end
	end
	
	%% show error
	rethrow(ME);
end