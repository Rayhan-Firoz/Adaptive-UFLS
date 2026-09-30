function twelve_exportSheddingScheme( ...
    data, op, result, ufls, zone, bus, feeder, post, result11)

%==========================================================================
% MODULE 12
% EXPORT UFLS SHEDDING SCHEME TO EXCEL
%
% Only the CURRENT / TRIPPED generator contingency is exported.
%
% Excel file:
%
%   DD-MM-YYYY HH-MM UFLS_Shedding_Scheme.xlsx
%
% Example:
%
%   08-09-2026 18-25 UFLS_Shedding_Scheme.xlsx
%
% The file is saved in the SAME DIRECTORY as this MATLAB file.
%
% Excel sheets:
%
%   1. Summary
%   2. Bus_Shedding
%   3. Feeder_Shedding
%   4. Generator
%
%==========================================================================


%% ========================================================================
% 1. BASIC PARAMETERS
% =========================================================================

Sbase = data.Sbase(1);

nBus = length(data.bus);

nGen = length(data.genBus);


%% ========================================================================
% 2. CURRENT / TRIPPED GENERATOR
% =========================================================================

if isfield(op,'tripGen') && ~isempty(op.tripGen)

    tripGen = round(op.tripGen);

elseif isfield(result11,'tripGen') && ...
       ~isempty(result11.tripGen)

    tripGen = round(result11.tripGen);

else

    error( ...
        'Module 12: current tripped generator is unavailable.');

end


if ~isscalar(tripGen) || ...
   ~isfinite(tripGen) || ...
   tripGen < 1 || ...
   tripGen > nGen

    error( ...
        'Module 12: invalid tripGen = %g.', ...
        tripGen);

end


tripBus = data.genBus(tripGen);


%% ========================================================================
% 3. CREATE OUTPUT FILENAME
% =========================================================================
%
% Windows does not allow "/" or ":" inside filenames.
%
% Therefore:
%
%   dd/mm/yyyy -> dd-mm-yyyy
%   hh:min     -> hh-min
%
% The file is saved in the same directory as this MATLAB function.
% =========================================================================

timeStamp = datestr(now,'dd-mm-yyyy HH-MM');


codeFolder = fileparts(mfilename('fullpath'));


filename = fullfile( ...
    codeFolder, ...
    [timeStamp ' UFLS_Shedding_Scheme.xlsx']);


%% ========================================================================
% 4. LOAD FACTOR
% =========================================================================

if isfield(op,'LF')

    LF = op.LF;

else

    LF = NaN;

end


%% ========================================================================
% 5. SOLAR FACTOR
% =========================================================================
%
% Module 2 stores the current solar factor as:
%
%   op.SF
%
% =========================================================================

if isfield(op,'SF')

    sF = op.SF;

else

    sF = NaN;

end


%% ========================================================================
% 6. REQUIRED SHEDDING
% =========================================================================

if isfield(ufls,'requiredShedding_MW')

    requiredSheddingMW = ...
        double(ufls.requiredShedding_MW);

elseif isfield(ufls,'Pshed_MW')

    requiredSheddingMW = ...
        double(ufls.Pshed_MW);

else

    error( ...
        'Module 12: required shedding is missing from Module 6 output.');

end


%% ========================================================================
% 7. ACTUAL FEEDER SHEDDING
% =========================================================================

if isfield(feeder,'totalPshed_MW')

    actualNormalShedMW = ...
        double(feeder.totalPshed_MW);

elseif isfield(feeder,'Pshed_MW')

    actualNormalShedMW = ...
        sum(double(feeder.Pshed_MW));

else

    actualNormalShedMW = 0;

end


%% ========================================================================
% 8. PQ NON-SHEDABLE FALLBACK
% =========================================================================
%
% Current Module 9 protects non-shedable load.
%
% If a fallback field exists, read it.
% Otherwise it is zero.
%
% =========================================================================

actualPQFallbackMW = 0;


if isfield(feeder,'busCriticalShed_MW')

    actualPQFallbackMW = ...
        sum(double(feeder.busCriticalShed_MW));

elseif isfield(feeder,'criticalShed_MW')

    actualPQFallbackMW = ...
        sum(double(feeder.criticalShed_MW));

end


%% ========================================================================
% 9. TOTAL ACTUAL SHEDDING
% =========================================================================

actualTotalShedMW = ...
    actualNormalShedMW + ...
    actualPQFallbackMW;


allocationErrorMW = ...
    actualTotalShedMW - ...
    requiredSheddingMW;


%% ========================================================================
% 10. INITIAL FREQUENCY
% =========================================================================

if isfield(result11,'initialFrequency')

    initialFrequency = ...
        double(result11.initialFrequency);

else

    initialFrequency = 50.0;

end


%% ========================================================================
% 11. FREQUENCY WITHOUT UFLS
% =========================================================================
%
% IMPORTANT:
%
% Module 6 stores this value as:
%
%   ufls.frequencyWithoutShedding_Hz
%
% =========================================================================

if isfield(ufls,'frequencyWithoutShedding_Hz')

    frequencyWithoutUFLS = ...
        double(ufls.frequencyWithoutShedding_Hz);

else

    error([ ...
        'Module 12: Frequency without UFLS is missing.' ...
        newline ...
        'Expected field: ufls.frequencyWithoutShedding_Hz']);

end


%% ========================================================================
% 12. FINAL FREQUENCY
% =========================================================================

if isfield(result11,'finalFrequency')

    finalFrequency = ...
        double(result11.finalFrequency);

else

    finalFrequency = NaN;

end


%% ========================================================================
% 13. FINAL FREQUENCY RECOVERY
% =========================================================================

if isfield(result11,'finalRecovered')

    if logical(result11.finalRecovered)

        finalFrequencyRecovery = ...
            'RECOVERED';

    else

        finalFrequencyRecovery = ...
            'NOT RECOVERED';

    end

elseif isfinite(finalFrequency)

    if finalFrequency >= data.fTarget(1)

        finalFrequencyRecovery = ...
            'RECOVERED';

    else

        finalFrequencyRecovery = ...
            'NOT RECOVERED';

    end

else

    finalFrequencyRecovery = '';

end


%% ========================================================================
% 14. GENERATION LOSS
% =========================================================================
%
% result.Pg is the pre-contingency NR generator output in pu.
%
% =========================================================================

if isfield(result,'Pg')

    generationLossMW = ...
        abs(double(result.Pg(tripGen))) * Sbase;

elseif isfield(op,'Pg')

    generationLossMW = ...
        abs(double(op.Pg(tripGen))) * Sbase;

else

    error( ...
        'Module 12: pre-trip generator power is unavailable.');

end


%% ========================================================================
% 15. SUMMARY SHEET
% =========================================================================
%
% ONLY the requested parameters are included.
%
% =========================================================================

SummaryParameter = { ...
    'Tripped Generator'; ...
    'Tripped Bus'; ...
    'Load Factor'; ...
    'Solar Factor (sF)'; ...
    'Generation Loss (MW)'; ...
    'Required Shedding (MW)'; ...
    'Initial Frequency (Hz)'; ...
    'Frequency Without UFLS (Hz)'; ...
    'Final Frequency (Hz)'; ...
    'Final Frequency Recovery'};


SummaryValue = { ...
    tripGen; ...
    tripBus; ...
    LF; ...
    sF; ...
    generationLossMW; ...
    requiredSheddingMW; ...
    initialFrequency; ...
    frequencyWithoutUFLS; ...
    finalFrequency; ...
    finalFrequencyRecovery};


SummaryTable = table( ...
    SummaryParameter, ...
    SummaryValue, ...
    'VariableNames', ...
    {'Parameter','Value'});


writetable( ...
    SummaryTable, ...
    filename, ...
    'Sheet','Summary');


%% ========================================================================
% 16. BUS SHEDDING SHEET
% =========================================================================
%
% Columns:
%
%   Bus
%   Zone
%   FVSI Rank
%   Target Shed MW
%   Normal Shed MW
%   PQ Non-Shedable Shed MW
%   Total Shed MW
%
% FVSI column is intentionally OMITTED.
%
% =========================================================================

busNumber = ...
    data.bus(:);


% -------------------------------------------------------------------------
% Zone
% -------------------------------------------------------------------------

if isfield(bus,'zoneID')

    busZone = ...
        bus.zoneID(:);

else

    busZone = ...
        zeros(nBus,1);

end


% -------------------------------------------------------------------------
% FVSI Rank
% -------------------------------------------------------------------------

if isfield(bus,'fvsiRank')

    busFVSIrank = ...
        bus.fvsiRank(:);

else

    busFVSIrank = ...
        zeros(nBus,1);

end


% -------------------------------------------------------------------------
% Target shedding
% -------------------------------------------------------------------------

if isfield(bus,'Pshed_MW')

    busTarget = ...
        bus.Pshed_MW(:);

else

    busTarget = ...
        zeros(nBus,1);

end


% -------------------------------------------------------------------------
% Normal shedding
%
% Module 8 Pshed_MW is the bus-level allocation target.
% Module 9 gives the actual feeder-based bus shedding.
% -------------------------------------------------------------------------

if isfield(feeder,'busShed_MW')

    busNormalShed = ...
        feeder.busShed_MW(:);

else

    busNormalShed = ...
        zeros(nBus,1);

end


% -------------------------------------------------------------------------
% PQ non-shedable fallback
% -------------------------------------------------------------------------

busCriticalShed = ...
    zeros(nBus,1);


if isfield(bus,'busCriticalShed_MW')

    busCriticalShed = ...
        bus.busCriticalShed_MW(:);

elseif isfield(bus,'criticalShed_MW')

    busCriticalShed = ...
        bus.criticalShed_MW(:);

elseif isfield(feeder,'busCriticalShed_MW')

    busCriticalShed = ...
        feeder.busCriticalShed_MW(:);

end


% -------------------------------------------------------------------------
% Resize vectors if necessary
% -------------------------------------------------------------------------

busZone = ...
    localResizeVector(busZone,nBus,0);


busFVSIrank = ...
    localResizeVector(busFVSIrank,nBus,0);


busTarget = ...
    localResizeVector(busTarget,nBus,0);


busNormalShed = ...
    localResizeVector(busNormalShed,nBus,0);


busCriticalShed = ...
    localResizeVector(busCriticalShed,nBus,0);


% -------------------------------------------------------------------------
% Total bus shedding
% -------------------------------------------------------------------------

busTotalShed = ...
    busNormalShed + ...
    busCriticalShed;


% -------------------------------------------------------------------------
% Build table
% -------------------------------------------------------------------------

BusTable = table( ...
    busNumber, ...
    busZone, ...
    busFVSIrank, ...
    busTarget, ...
    busNormalShed, ...
    busCriticalShed, ...
    busTotalShed, ...
    'VariableNames', ...
    { ...
    'Bus', ...
    'Zone', ...
    'FVSI_Rank', ...
    'Target_Shed_MW', ...
    'Normal_Shed_MW', ...
    'PQ_NonShedable_Shed_MW', ...
    'Total_Shed_MW'});


% -------------------------------------------------------------------------
% Only export buses actually involved in shedding.
% -------------------------------------------------------------------------

busMask = ...
    (busTarget > 1e-9) | ...
    (busTotalShed > 1e-9);


BusTable = ...
    BusTable(busMask,:);


writetable( ...
    BusTable, ...
    filename, ...
    'Sheet','Bus_Shedding');


%% ========================================================================
% 17. FEEDER SHEDDING SHEET
% =========================================================================
%
% Columns:
%
%   Feeder ID
%   Source Bus
%   Feeder Load MW
%   Normal Shedable MW
%   Protected MW
%   Actual Shed MW
%   Shedding Status
%
% Selected column is intentionally OMITTED.
%
% =========================================================================

nFeeder = ...
    length(feeder.Pshed_MW);


% -------------------------------------------------------------------------
% Feeder ID
% -------------------------------------------------------------------------

if isfield(feeder,'id')

    feederID = ...
        feeder.feederID(:);

else

    feederID = ...
        (1:nFeeder).';

end


% -------------------------------------------------------------------------
% Source bus
% -------------------------------------------------------------------------

if isfield(feeder,'sourceBus')

    feederBus = ...
        feeder.sourceBus(:);

else

    feederBus = ...
        nan(nFeeder,1);

end


% -------------------------------------------------------------------------
% Feeder load
% -------------------------------------------------------------------------

if isfield(feeder,'load_MW')

    feederLoad = ...
        feeder.load_MW(:);

elseif isfield(op,'feederLoad_MW')

    feederLoad = ...
        op.feederLoad_MW(:);

else

    feederLoad = ...
        nan(nFeeder,1);

end


% -------------------------------------------------------------------------
% Normal shedable feeder load
% -------------------------------------------------------------------------

if isfield(feeder,'normalShedable_MW')

    feederNormalCapacity = ...
        feeder.normalShedable_MW(:);

elseif isfield(op,'feederNormalShedable_MW')

    feederNormalCapacity = ...
        op.feederNormalShedable_MW(:);

else

    feederNormalCapacity = ...
        zeros(nFeeder,1);

end


% -------------------------------------------------------------------------
% Protected feeder load
% -------------------------------------------------------------------------

if isfield(feeder,'nonShedable_MW')

    feederProtected = ...
        feeder.nonShedable_MW(:);

elseif isfield(op,'feederNonShedable_MW')

    feederProtected = ...
        op.feederNonShedable_MW(:);

else

    feederProtected = ...
        zeros(nFeeder,1);

end


% -------------------------------------------------------------------------
% Actual feeder shedding
% -------------------------------------------------------------------------

feederShed = ...
    feeder.Pshed_MW(:);


% -------------------------------------------------------------------------
% Resize
% -------------------------------------------------------------------------

feederBus = ...
    localResizeVector(feederBus,nFeeder,NaN);


feederLoad = ...
    localResizeVector(feederLoad,nFeeder,NaN);


feederNormalCapacity = ...
    localResizeVector( ...
    feederNormalCapacity,nFeeder,0);


feederProtected = ...
    localResizeVector( ...
    feederProtected,nFeeder,0);


feederShed = ...
    localResizeVector(feederShed,nFeeder,0);


% -------------------------------------------------------------------------
% Shedding status
% -------------------------------------------------------------------------

feederStatusText = ...
    repmat({'Not Selected'},nFeeder,1);


for k = 1:nFeeder

    if feederShed(k) > 1e-9

        if abs( ...
                feederShed(k) - ...
                feederNormalCapacity(k)) <= 1e-6

            feederStatusText{k} = ...
                'Full Normal Shedable Portion';

        else

            feederStatusText{k} = ...
                'Partial Normal Shedable Portion';

        end

    end

end


% -------------------------------------------------------------------------
% Build table
% -------------------------------------------------------------------------

FeederTable = table( ...
    feederID, ...
    feederBus, ...
    feederLoad, ...
    feederNormalCapacity, ...
    feederProtected, ...
    feederShed, ...
    feederStatusText, ...
    'VariableNames', ...
    { ...
    'Feeder_ID', ...
    'Source_Bus', ...
    'Feeder_Load_MW', ...
    'Normal_Shedable_MW', ...
    'Protected_MW', ...
    'Actual_Shed_MW', ...
    'Shedding_Status'});


% -------------------------------------------------------------------------
% Export only feeders that actually shed load.
% -------------------------------------------------------------------------

feederMask = ...
    feederShed > 1e-9;


FeederTable = ...
    FeederTable(feederMask,:);


writetable( ...
    FeederTable, ...
    filename, ...
    'Sheet','Feeder_Shedding');


%% ========================================================================
% 18. ZONE SUMMARY
% =========================================================================
%
% Columns:
%
%   Zone
%   Required MW
%   Normal Allocated MW
%   Actual Shed MW
%   Remaining MW
%   Status
%
% =========================================================================

validZones = ...
    busZone(busZone > 0);


zoneID = ...
    unique(validZones);


nZone = ...
    length(zoneID);


zoneRequired = ...
    zeros(nZone,1);


zoneAllocated = ...
    zeros(nZone,1);


zoneActual = ...
    zeros(nZone,1);


zoneRemaining = ...
    zeros(nZone,1);


zoneStatus = ...
    repmat({'FEASIBLE'},nZone,1);


for z = 1:nZone

    zid = ...
        zoneID(z);


    idxBus = ...
        busZone == zid;


    zoneRequired(z) = ...
        sum(busTarget(idxBus));


    zoneAllocated(z) = ...
        sum(busNormalShed(idxBus));


    zoneActual(z) = ...
        sum(busTotalShed(idxBus));


    zoneRemaining(z) = ...
        zoneRequired(z) - ...
        zoneActual(z);


    if abs(zoneRemaining(z)) > 1e-6

        zoneStatus{z} = ...
            'CHECK';

    end

end


ZoneTable = table( ...
    zoneID, ...
    zoneRequired, ...
    zoneAllocated, ...
    zoneActual, ...
    zoneRemaining, ...
    zoneStatus, ...
    'VariableNames', ...
    { ...
    'Zone', ...
    'Required_MW', ...
    'Normal_Allocated_MW', ...
    'Actual_Shed_MW', ...
    'Remaining_MW', ...
    'Status'});


writetable( ...
    ZoneTable, ...
    filename, ...
    'Sheet','Zone_Summary');


%% ========================================================================
% 19. GENERATOR SHEET
% =========================================================================
%
% Columns:
%
%   Gen ID
%   Bus
%   Pre-Trip Pg MW
%   Headroom MW
%   Status
%
% H, Rating and Droop are intentionally OMITTED.
%
% =========================================================================

if isfield(data,'genID')

    genID = ...
        data.genID(:);

else

    genID = ...
        (1:nGen).';

end


genBusAll = ...
    data.genBus(:);


% -------------------------------------------------------------------------
% Pre-trip generator power
% -------------------------------------------------------------------------

if isfield(result,'Pg')

    genPgMW = ...
        double(result.Pg(:)) * Sbase;

elseif isfield(op,'Pg')

    genPgMW = ...
        double(op.Pg(:)) * Sbase;

else

    genPgMW = ...
        nan(nGen,1);

end


% -------------------------------------------------------------------------
% Generator headroom
% -------------------------------------------------------------------------

if isfield(data,'Pmax_MW')

    PmaxMW = ...
        data.Pmax_MW(:);

    genHeadroom = ...
        PmaxMW - genPgMW;

elseif isfield(data,'Pmax')

    PmaxMW = ...
        data.Pmax(:) * Sbase;

    genHeadroom = ...
        PmaxMW - genPgMW;

else

    genHeadroom = ...
        nan(nGen,1);

end


% -------------------------------------------------------------------------
% Generator status
% -------------------------------------------------------------------------

genStatusText = ...
    repmat({'Active'},nGen,1);


genStatusText{tripGen} = ...
    'TRIPPED';


% -------------------------------------------------------------------------
% Resize
% -------------------------------------------------------------------------

genPgMW = ...
    localResizeVector(genPgMW,nGen,NaN);


genHeadroom = ...
    localResizeVector(genHeadroom,nGen,NaN);


% -------------------------------------------------------------------------
% Build table
% -------------------------------------------------------------------------

GeneratorTable = table( ...
    genID, ...
    genBusAll, ...
    genPgMW, ...
    genHeadroom, ...
    genStatusText, ...
    'VariableNames', ...
    { ...
    'Gen_ID', ...
    'Bus', ...
    'PreTrip_Pg_MW', ...
    'Headroom_MW', ...
    'Status'});


writetable( ...
    GeneratorTable, ...
    filename, ...
    'Sheet','Generator');


%% ========================================================================
% 20. FORMAT EXCEL TO TWO DECIMAL PLACES
% =========================================================================
%
% This section changes DISPLAY formatting only.
%
% It does not change the MATLAB calculations.
%
% =========================================================================

try

    excel = actxserver('Excel.Application');

    excel.Visible = false;


    % IMPORTANT:
    % filename already contains the complete path.
    %
    % Do NOT use:
    %
    %   fullfile(pwd,filename)
    %
    % here.

    workbook = ...
        excel.Workbooks.Open(filename);


    sheetNames = { ...
        'Summary', ...
        'Bus_Shedding', ...
        'Feeder_Shedding', ...
        'Zone_Summary', ...
        'Generator'};


    for k = 1:length(sheetNames)

        sheet = ...
            workbook.Worksheets.Item(sheetNames{k});


        % Two decimal places for all numerical cells.

        sheet.UsedRange.NumberFormat = ...
            '0.00';


        % Automatically fit columns.

        sheet.UsedRange.Columns.AutoFit;

    end


    workbook.Save;

    workbook.Close;

    excel.Quit;

    delete(excel);


catch ME

    warning( ...
        'Module 12: Excel formatting could not be applied. %s', ...
        ME.message);

end


%% ========================================================================
% 21. PRINT MODULE 12 RESULT
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' MODULE 12: EXPORT UFLS SHEDDING SCHEME\n');
fprintf('============================================================\n');


fprintf('\n');


fprintf('Current contingency:\n');

fprintf('  Tripped generator = Gen %d\n', ...
    tripGen);

fprintf('  Tripped bus       = Bus %d\n', ...
    tripBus);


fprintf('\n');


fprintf('Operating condition:\n');

fprintf('  Load factor       = %.2f\n', ...
    LF);

fprintf('  Solar factor (sF) = %.2f\n', ...
    sF);


fprintf('\n');


fprintf('UFLS summary:\n');

fprintf('  Generation loss          = %.2f MW\n', ...
    generationLossMW);

fprintf('  Required shedding        = %.2f MW\n', ...
    requiredSheddingMW);

fprintf('  Actual total shedding    = %.2f MW\n', ...
    actualTotalShedMW);

fprintf('  Initial frequency        = %.2f Hz\n', ...
    initialFrequency);

fprintf('  Frequency without UFLS  = %.2f Hz\n', ...
    frequencyWithoutUFLS);

fprintf('  Final frequency          = %.2f Hz\n', ...
    finalFrequency);

fprintf('  Final frequency recovery = %s\n', ...
    finalFrequencyRecovery);


fprintf('\n');


fprintf('Excel file saved at:\n');

fprintf('  %s\n', ...
    filename);


fprintf('\n');


fprintf('Sheets exported:\n');

fprintf('  Summary\n');
fprintf('  Bus_Shedding\n');
fprintf('  Feeder_Shedding\n');
fprintf('  Zone_Summary\n');
fprintf('  Generator\n');


fprintf('\n');

fprintf('MODULE 12 COMPLETE\n');

fprintf('============================================================\n');


end


%% ========================================================================
% LOCAL HELPER FUNCTION
% =========================================================================

function v = localResizeVector(v,n,fillValue)

v = v(:);


if length(v) == n

    return;

end


if length(v) > n

    v = v(1:n);

else

    v(end+1:n,1) = fillValue;

end

end