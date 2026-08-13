clc;
clear;
close all;

%% ====================================================================
%  1. READ IMAGE & ADJUST CONTRAST
%  ====================================================================
[file,path] = uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.bmp'},...
    'Select Grayscale SEM Image');
if isequal(file,0)
    error('No image selected.');
end
img = imread(fullfile(path,file));

% Safety check: If the grayscale image was accidentally saved in an RGB format, 
% extract just the first channel to keep it 2D.
if ndims(img) == 3
    img = img(:,:,1);
end

% Adjust contrast automatically to enhance phase separation
grayImg = imadjust(img); 
[m, n] = size(grayImg);

%% ====================================================================
%  2. SELECT ROI (Menu Loop)
%  ====================================================================
roiConfirmed = false;

while ~roiConfirmed
    % Present Options
    choice = menu('Select ROI Method:', ...
        '1. Draw Polygon', ...
        '2. Manual Coordinates (X, Y, W, H)', ...
        '3. Automatic Specimen Detection');
    
    % Initialize an empty mask of the same size as the image
    mask = false(m, n);
    
    switch choice
        case 1
            %% Method 1: Polygon
            figure('Name','Select ROI');
            imshow(grayImg,[]);
            title('Draw Polygon ROI then Double Click');
            roi = drawpolygon('LineWidth',2);
            mask = createMask(roi);
            close;
            
        case 2
            %% Method 2: Manual Coordinates
            disp('Enter ROI coordinates');
            x = round(input('Start X = '));
            y = round(input('Start Y = '));
            w = round(input('Width = '));
            h = round(input('Height = '));
            
            % Enforce boundaries to prevent indexing errors
            x = max(1, min(x, n));
            y = max(1, min(y, m));
            w = max(1, min(w, n - x + 1));
            h = max(1, min(h, m - y + 1));
            
            mask(y:y+h-1, x:x+w-1) = true;
            
        case 3
            %% Method 3: Automatic Specimen Detection
            disp('Detecting Specimen ROI...');
            level = graythresh(grayImg);
            bw_thresh = imbinarize(grayImg, level);
            bw_edge = edge(grayImg, 'canny');
            
            bw_combined = bw_thresh | bw_edge;
            
            se = strel('disk', 5);
            bw_morph = imclose(bw_combined, se);
            bw_filled = imfill(bw_morph, 'holes');
            
            mask = bwareafilt(bw_filled, 1);
            
        otherwise
            error('ROI Selection Cancelled.');
    end
    
    % Apply Mask
    roiImage = double(grayImg); % Convert to double for math/NaN operations later
    roiImage(~mask) = 0; % Set pixels outside ROI to 0
    
    % Display Current Selection for Confirmation
    hFig = figure('Name', 'ROI Preview');
    imagesc(roiImage);
    colormap('gray');
    colorbar;
    axis image;
    title('Preview of Selected ROI');
    
    % Final Confirmation
    confirmChoice = menu('Are you satisfied with this ROI?', 'Yes, Continue', 'No, Select Again');
    
    if confirmChoice == 1
        roiConfirmed = true; % Exit loop
        disp('ROI Confirmed.');
    else
        close(hFig); % Close preview and loop again
        disp('Restarting ROI selection...');
    end
end

% Extract 1D array of valid pixel intensities
pixels = roiImage(mask); 
fprintf('\nImage Size = %d x %d\n', m, n);
fprintf('Total Pixels in ROI = %d\n', length(pixels));

%% ====================================================================
%  3. MULTIPLE PHASE DETECTION
%  ====================================================================
nPhases = input('\nEnter number of phases: ');
title(sprintf('Click ONE representative pixel from each of the %d phases', nPhases));

% Collect Phase Samples
[px, py] = ginput(nPhases);
px = round(px);
py = round(py);

grayLevels = zeros(1, nPhases);
for i=1:nPhases
    grayLevels(i) = roiImage(py(i), px(i));
end

% Sort grayscale values
grayLevels = sort(grayLevels);
fprintf('\nRepresentative Gray Levels\n');
disp(grayLevels)

%% Automatic Thresholds
thresholds = zeros(1,nPhases-1);
for i=1:nPhases-1
    thresholds(i) = round((grayLevels(i)+grayLevels(i+1))/2);
end
fprintf('\nThresholds\n');
disp(thresholds)

%% Phase Matrix Calculation
phase = zeros(size(roiImage));
for i=1:m
    for j=1:n
        % Only classify pixels that are INSIDE the polygon mask
        if mask(i,j) 
            pixel = roiImage(i,j);
            assigned = false;
            
            for k=1:length(thresholds)
                if pixel <= thresholds(k)
                    phase(i,j) = k;
                    assigned = true;
                    break;
                end
            end
            
            if ~assigned
                phase(i,j) = nPhases;
            end
        end
    end
end

%% ====================================================================
%  4. VISUALIZATION & AREA FRACTION CALCULATION
%  ====================================================================
% Display Phases: Set outside mask to NaN so it appears transparent
phaseDisp = double(phase);
phaseDisp(~mask) = NaN; 

figure('Name', 'Final Detected Phases');
imagesc(phaseDisp);
axis image;
colormap(parula(nPhases)); % Use a distinct colormap for phases
colorbar('Ticks', 1:nPhases);
title('Detected Phases (Inside ROI)');

%% Area Fraction & Pie Chart Data
% Total valid pixels inside the mask
total = sum(mask(:)); 
fprintf('\n---------------------------------\n');

% Initialize arrays to hold data for the pie chart
areaFractions = zeros(1, nPhases);
pieLabels = cell(1, nPhases);

for k=1:nPhases
    % Count how many pixels were assigned to phase k
    phase_pixels = sum(phase(:)==k);
    
    % Calculate percentage
    fraction = 100 * phase_pixels / total;
    
    % Store for pie chart
    areaFractions(k) = fraction;
    pieLabels{k} = sprintf('Phase %d\n(%.1f%%)', k, fraction);
    
    % Print to command window
    fprintf('Phase %d\n',k);
    fprintf('Pixels       : %d\n',phase_pixels);
    fprintf('Area Fraction: %.2f %%\n', fraction);
    fprintf('Representative Gray = %d\n\n', grayLevels(k));
end

%% Plot Pie Chart
figure('Name', 'Area Fractions');
pie(areaFractions, pieLabels);
title('Phase Area Fractions');
