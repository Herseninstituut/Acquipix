function [cellPoints,strFile,strPath] = PH_OpenCoordsFile(strDefaultPath)
	
	%pre-allocate output
	cellPoints = [];
	
	%select file
	try
		strOldPath = cd(strDefaultPath);
	catch
		strOldPath = cd();
	end
	[strFile,strPath]=uigetfile('probe_ccf.mat','Select probe coordinate file');
	cd(strOldPath);
	if isempty(strFile) || (numel(strFile)==1 && strFile==0)
		return;
	end
	
	%load
	sLoad = load(fullpath(strPath,strFile));
	if isfield(sLoad,'probe_ccf') && isstruct(sLoad.probe_ccf) && isfield(sLoad.probe_ccf,'points')
		%AP_histology
		cellPoints = {sLoad.probe_ccf.points};
	elseif isfield(sLoad,'pointList') && isstruct(sLoad.pointList) && isfield(sLoad.pointList,'pointList')
		%sharp track
		cellPoints = sLoad.pointList.pointList(:,1); %cell arrays
		
		%invert x/y & depth
		cellPoints = cellfun(@(x) (x(end:-1:1,[3 2 1])),cellPoints,'UniformOutput',false);
		
	else
		try
			error([mfilename ':FileTypeNotRecognized'],'File is of unknown format');
		catch ME
			strStack = sprintf('Error in %s (Line %d)',ME.stack(1).name,ME.stack(1).line);
			errordlg(sprintf('%s\n%s',ME.message,strStack),'Probe coord error')
			return;
		end
	end
	