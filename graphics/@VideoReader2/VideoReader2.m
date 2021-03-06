classdef (CaseInsensitiveProperties=true, TruncatedProperties=true) ...
         VideoReader2 < hgsetget
% VIDEOREADER2 Create a multimedia reader object that handles uncompressed
% AVIs and multiframe Tiffs
%
%   Otherwise identical to VideoReader.


    %------------------------------------------------------------------
    % General properties (in alphabetic order)
    %------------------------------------------------------------------
    properties(GetAccess='public', SetAccess='private')
        Name            % Name of the file to be read.
        Path            % Path of the file to be read.
    end
    
    properties(GetAccess='public', SetAccess='private', Dependent)
        Duration        % Total length of file in seconds.
    end
    
    properties(GetAccess='public', SetAccess='public')
        Tag = '';       % Generic string for the user to set.
    end
    
    properties(GetAccess='public', SetAccess='private', Dependent) 
        Type            % Classname of the object.
    end
    
    properties(GetAccess='public', SetAccess='public')
        UserData        % Generic field for any user-defined data.
        isaviread
        isphantom
    end
    
    %------------------------------------------------------------------
    % Video properties (in alphabetic order)
    %------------------------------------------------------------------
    properties(GetAccess='public', SetAccess='private')
        BitsPerPixel    % Bits per pixel of the video data.
        FrameRate       % Frame rate of the video in frames per second.
        Height          % Height of the video frame in pixels.
        NumberOfFrames  % Total number of frames in the video stream. 
        VideoFormat     % Video format as it is represented in MATLAB.
        Width           % Width of the video frame in pixels.
    end
    
    %------------------------------------------------------------------
    % Undocumented properties
    %------------------------------------------------------------------
    properties(GetAccess='public', SetAccess='private')
        AudioCompression
        NumberOfAudioChannels
        VideoCompression
    end
    
    properties(Access='private', Hidden)
        vid
        cine
        info
        tifinfo
        istimestamp
    end
    %------------------------------------------------------------------
    % Documented methods
    %------------------------------------------------------------------    
    methods(Access='public')
    
        %------------------------------------------------------------------
        % Lifetime
        %------------------------------------------------------------------
        function obj = VideoReader2(fileName, varargin)

            % If no file name provided.
            if nargin == 0
                error(message('MATLAB:audiovideo:VideoReader:noFile'));
            end

            obj.isaviread = ~isempty(which('aviread'));
            obj.isphantom = exist('LoadPhantomLibraries','file');
            obj.cine = struct([]);
            
            [pn,fn,ext] = fileparts(fileName);
            
            if (strcmpi(ext,'.tif') || strcmpi(ext, '.tiff'))
                obj.tifinfo = imfinfo(fileName);
                obj.vid = struct([]);
                obj.info = struct([]);
                
                obj.Path = pn;
                obj.Name = [fn ext];
                try
                    I = imread(fileName,1, 'Info',obj.tifinfo);
                    getPCOtimestamp(I);
                    obj.istimestamp = true;
                catch err
                    if strcmp(err.identifier, 'getpcotimestamp:notimestamp')
                        obj.istimestamp = false;
                    else
                        rethrow(err);
                    end
                end
            elseif (strcmpi(ext,'.cine') && obj.isphantom)
                LoadPhantomLibraries();
                RegisterPhantom(true); %Register the Phantom dll's ignoring connected cameras. 
                [HRES, cineHandle] = PhNewCineFromFile(fileName);
                if (HRES<0)
                    [msg] = PhGetErrorMessage( HRES );
                    error(['Cine handle creation error: ' msg]);
                end
                obj.vid = struct([]);
                obj.info = struct([]);
                obj.Path = pn;
                obj.Name = [fn ext];

                pFirstIm = libpointer('int32Ptr',0);
                PhGetCineInfo(cineHandle, PhFileConst.GCI_FIRSTIMAGENO, pFirstIm);
                firstIm = pFirstIm.Value;
                pImCount = libpointer('uint32Ptr',0);
                PhGetCineInfo(cineHandle, PhFileConst.GCI_IMAGECOUNT, pImCount);
                lastIm = int32(double(firstIm) + double(pImCount.Value) - 1);
                
                %get cine image buffer size
                pInfVal = libpointer('uint32Ptr',0);
                PhGetCineInfo(cineHandle, PhFileConst.GCI_MAXIMGSIZE, pInfVal);
                imgSizeInBytes = pInfVal.Value;

                pInfVal = libpointer('uint32Ptr',0);
                PhGetCineInfo(cineHandle, PhFileConst.GCI_FRAMERATE, pInfVal);
                framerate = pInfVal.Value;
                
                pInfVal = libpointer('uint32Ptr',0);
                PhGetCineInfo(cineHandle, PhFileConst.GCI_IMWIDTH, pInfVal);
                w = pInfVal.Value;
                
                pInfVal = libpointer('uint32Ptr',0);
                PhGetCineInfo(cineHandle, PhFileConst.GCI_IMHEIGHT, pInfVal);
                h = pInfVal.Value;
                
                %The image flip for GetCineImage function is inhibated.
                pInfVal = libpointer('int32Ptr',false);
                PhSetCineInfo(cineHandle, PhFileConst.GCI_VFLIPVIEWACTIVE, pInfVal);

                obj.cine(1).handle = cineHandle;
                obj.cine.nframes = lastIm-firstIm+1;
                obj.cine.firstIm = firstIm;
                obj.cine.imgSize = imgSizeInBytes;
                obj.cine.width = w;
                obj.cine.height = h;
                obj.cine.fps = framerate;
            else
                try
                    obj.vid = VideoReader(fileName, varargin{:});
                catch err
                    if (strcmp(err.identifier, 'MATLAB:audiovideo:VideoReader:FileInit') && ...
                            obj.isaviread)
                        obj.vid = struct([]);
                        w = warning('off','MATLAB:audiovideo:aviinfo:FunctionToBeRemoved');
                        obj.info = aviinfo(fileName);       %#ok
                        warning(w);

                        set(obj,'Path',pn);
                        set(obj,'Name',[fn ext]);
                    else
                        rethrow(err);
                    end
                end
            end
            
            % Set properties that user passed in.
            if nargin > 1
                set(obj, varargin{:});
            end
        end


        %------------------------------------------------------------------
        % Operations
        %------------------------------------------------------------------        
        function varargout = read(obj, varargin)
            if ~isempty(obj.vid)
                v = read(obj.vid,varargin{:});
                varargout = {v};
                if (nargout > 1)
                    varargout(2:3) = {varargin{1},[]};
                end                    
            elseif ~isempty(obj.tifinfo)
                fn = fullfile(obj.Path,obj.Name);
                I = imread(fn, varargin{1}, 'Info',obj.tifinfo, varargin{:});
                varargout = {I};
                if ((nargout > 1) && obj.istimestamp)
                    [dv,imnum] = getPCOtimestamp(fn);
                    varargout(2:3) = {imnum,dv};
                end
            elseif ~isempty(obj.cine)
                if ((nargin == 3) && ischar(varargin{2}))
                    frameopt = varargin{2};
                else
                    frameopt = 'fromstart';
                end
                switch lower(frameopt)
                    case 'fromtrigger'
                        fr = varargin{1};
                    case 'fromstart'
                        fr = varargin{1} + obj.cine.firstIm-1;
                    otherwise
                        fr = varargin{1} + obj.cine.firstIm-1;
                end
                
                if ((fr < obj.cine.firstIm) || (fr > obj.cine.firstIm + obj.cine.nframes))
                    error('VideoReader2:outofrange','Frame is out of range for CINE file');
                end
                %Create the image reange to be readed
                imgRange = get(libstruct('tagIMRANGE'));
                %take one image at imageNo
                imgRange.First = fr;
                imgRange.Cnt = 1;
                
                % Read the cine image into the buffer 
                %The image will have image processings applied 
                [HRES, unshiftedIm, imgHeader] = PhGetCineImage(obj.cine.handle, ...
                    imgRange, obj.cine.imgSize);

                % Read image information from header
                isColorImage = IsColorHeader(imgHeader);
                is16bppImage = Is16BitHeader(imgHeader);

                % Transform 1D image pixels to 1D/3D image pixels to be used with MATLAB
                if (HRES >= 0)
                    [unshiftedIm] = ExtractImageMatrixFromImageBuffer(unshiftedIm, imgHeader);
                    if (isColorImage)
                        samplespp = 3;
                    else
                        samplespp = 1;
                    end
                    bps = GetEffectiveBitsFromIH(imgHeader);
                    [I, ~] = ConstructMatlabImage(unshiftedIm, imgHeader.biWidth, imgHeader.biHeight, samplespp, bps);
                    varargout = {I};
                end
            else
                w = warning('off','MATLAB:audiovideo:aviread:FunctionToBeRemoved');
                fr = aviread(fullfile(obj.Path,obj.Name),varargin{:});  %#ok
                warning(w);
                varargout = {fr.cdata};
                if (nargout > 1)
                    varargout(2:3) = {varargin{1},[]};
                end                    
            end
        end
        
        function N = getmaxframes(obj)
            if ~isempty(obj.tifinfo) && obj.istimestamp
                fn = fullfile(obj.Path,obj.Name);
                I1 = imread(fn, 1, 'Info',obj.tifinfo);
                I2 = imread(fn, numel(obj.tifinfo), 'Info',obj.tifinfo);
                [~,imnum1] = getPCOtimestamp(I1);
                [~,imnum2] = getPCOtimestamp(I2);
                N = imnum2 - imnum1 + 1;
            elseif ~isempty(obj.cine)
                N = obj.cine.nframes;
            else
                N = get(obj,'NumberOfFrames');
            end
        end
        
        %------------------------------------------------------------------        
        % Overrides of hgsetset
        %------------------------------------------------------------------        
        function getdisp(obj)
            if ~isempty(obj.vid)
                obj.vid.getdisp();
            else
                getdisp@hgsetget(obj);
            end
        end
        function setdisp(obj)
            if ~isempty(obj.vid)
                obj.vid.setdips();
            else
                setdisp@hgsetget(obj);
            end
        end

        %------------------------------------------------------------------        
        % Overrides of builtins
        %------------------------------------------------------------------ 
        function disp(obj)
            if ~isempty(obj.vid)
                obj.vid.display();
            elseif ~isempty(obj.cine)
                fprintf('Phantom CINE file ''%s''\n', obj.Name);
            elseif isempty(obj.tifinfo)
                fprintf('Multiframe tiff ''%s''\n', obj.Name);
            else
                fprintf('Uncompressed avi ''%s''\n', obj.Name);
            end
        end

        function display(obj)
            disp(obj);
        end
    end
    
    %------------------------------------------------------------------
    % Custom Getters/Setters
    %------------------------------------------------------------------
    methods
        % Properties that are not dependent on underlying object.
        function set.Tag(obj, value)
            if ~(ischar(value) || isempty(value))
                error(message('MATLAB:audiovideo:VideoReader:TagMustBeString'));
            end
            obj.Tag = value;
        end
        
        function value = get.Type(obj)
            value = class(obj);
        end
        
        % Properties that are dependent on underlying object.
        function value = get.Duration(obj)
            if ~isempty(obj.vid)
                value = obj.vid.Duration;
            elseif ~isempty(obj.cine)
                value = NaN;
            elseif ~isempty(obj.tifinfo)
                value = NaN;
            else
                value = obj.info.NumFrames / obj.info.FramesPerSecond;
            end
        end
        
        function value = get.Name(obj)
            if ~isempty(obj.vid)
                value = get(obj.vid,'Name');
            else
                value = obj.Name;
            end
        end
        
        function value = get.Path(obj)
            if ~isempty(obj.vid)
                value = get(obj.vid,'Path');
            else
                value = obj.Path;
            end
        end
        
        function value = get.BitsPerPixel(obj)
            if ~isempty(obj.vid)
                value = obj.vid.BitsPerPixel;
            elseif ~isempty(obj.cine)
                value = NaN;
            elseif ~isempty(obj.tifinfo)
                value = obj.tifinfo(1).BitsPerSample;
            else
                value = log2(obj.info.NumColormapEntries);
            end
        end
        
        function value = get.FrameRate(obj)
            if ~isempty(obj.vid)
                value = obj.vid.FrameRate;
            elseif ~isempty(obj.cine)
                value = obj.cine.fps;
            elseif ~isempty(obj.tifinfo)
                value = NaN;
            else
                value = obj.info.FramesPerSecond;
            end
        end
        
        function value = get.Height(obj)
            if ~isempty(obj.vid)
                value = obj.vid.Height;
            elseif ~isempty(obj.cine)
                value = obj.cine.height;
            elseif ~isempty(obj.tifinfo)
                value = obj.tifinfo(1).Height;
            else
                value = obj.info.Height;
            end
        end
        
        function value = get.NumberOfFrames(obj)
            if ~isempty(obj.vid)
                value = obj.vid.NumberOfFrames;
            elseif ~isempty(obj.cine)
                value = obj.cine.nframes;
            elseif ~isempty(obj.tifinfo)
                value = numel(obj.tifinfo);
            else
                value = obj.info.NumFrames;
            end
        end
        
        function value = get.VideoFormat(obj)
            if ~isempty(obj.vid)
                value = obj.vid.VideoFormat;
            elseif ~isempty(obj.cine)
                value = 'CINE';
            elseif ~isempty(obj.tifinfo)
                value = 'TIFF';
            else
                value = 'Uncompressed AVI';
            end
        end
        
        function value = get.Width(obj)
            if ~isempty(obj.vid)
                value = obj.vid.Width;
            elseif ~isempty(obj.cine)
                value = obj.cine.width;
            elseif ~isempty(obj.tifinfo)
                value = obj.tifinfo(1).Width;
            else
                value = obj.info.Width;
            end
        end
        
        function value = get.AudioCompression(obj)
            if ~isempty(obj.vid)
                value = obj.vid.AudioCompression;
            else
                warning('VideoReader2:NoSuchProperty',...
                    'No AudioCompression property');
                value = '';
            end
        end
        
        function value = get.NumberOfAudioChannels(obj)
            if ~isempty(obj.vid)
                value = obj.vid.NumberOfAudioChannels;
            else
                warning('VideoReader2:NoSuchProperty',...
                    'No NumberOfAudioChannels property');
                value = '';
            end
        end
        
        function value = get.VideoCompression(obj)
            if ~isempty(obj.vid)
                value = obj.vid.VideoCompression;
            elseif ~isempty(obj.tifinfo)
                value = obj.tifinfo(1).Compression;
            else
                value = 'Uncompressed AVI';
            end
        end
    end
    
    %------------------------------------------------------------------        
    % Undocumented methods
    %------------------------------------------------------------------
    methods (Access='public', Hidden)
        
        %------------------------------------------------------------------
        % Lifetime
        %------------------------------------------------------------------
        function delete(obj)
            % Delete VideoReader object.
            if ~isempty(obj.vid)
                delete(obj.vid);
            elseif ~isempty(obj.cine)
                UnregisterPhantom();
                UnloadPhantomLibraries();
            end
        end
   
    end
end
