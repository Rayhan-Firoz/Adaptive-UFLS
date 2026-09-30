function data = one_readInputData(filename)

clc

%% ============================================================
% MODULE 1
% READ INPUT DATA FROM EXCEL FILE
% ============================================================

%% ------------------------------------------------------------
% 1. READ BUS DATA
% ------------------------------------------------------------

busTable = readtable(filename,'Sheet','Bus_Data');

data.bus = busTable.Bus;
data.busType = busTable.Type;

data.Pload_MW = busTable.Pload_MW;
data.Qload_Mvar = busTable.Qload_Mvar;

data.V0 = busTable.Volt_pu;
data.angle0 = busTable.Angle_deg;

data.Vmax = busTable.Vmax_pu;
data.Vmin = busTable.Vmin_pu;


% Convert to column vectors

data.bus = data.bus(:);
data.busType = data.busType(:);

data.Pload_MW = data.Pload_MW(:);
data.Qload_Mvar = data.Qload_Mvar(:);

data.V0 = data.V0(:);
data.angle0 = data.angle0(:);

data.Vmax = data.Vmax(:);
data.Vmin = data.Vmin(:);


% Check bus number

if length(unique(data.bus)) ~= length(data.bus)

    error('Duplicate bus number found.');

end


% Check bus type

if any(data.busType ~= 1 & ...
       data.busType ~= 2 & ...
       data.busType ~= 3)

    error('Bus Type must be 1, 2, or 3.');

end


% Check load

if any(data.Pload_MW < 0)

    error('Negative bus load found.');

end


%% ------------------------------------------------------------
% 2. READ LINE DATA
% ------------------------------------------------------------

lineTable = readtable(filename,'Sheet','Line_Data');

data.fromBus = lineTable.From;
data.toBus = lineTable.To;

data.Rline = lineTable.R_pu;
data.Xline = lineTable.X_pu;
data.Bline = lineTable.B_pu;

data.tap = lineTable.Tap_Magnitude;
data.tapAngle = lineTable.Tap_Angle_deg;

data.lineStatus = lineTable.Status;


data.fromBus = data.fromBus(:);
data.toBus = data.toBus(:);

data.Rline = data.Rline(:);
data.Xline = data.Xline(:);
data.Bline = data.Bline(:);

data.tap = data.tap(:);
data.tapAngle = data.tapAngle(:);

data.lineStatus = data.lineStatus(:);


% Check line buses

if any(~ismember(data.fromBus,data.bus))

    error('Invalid From bus found in Line_Data.');

end

if any(~ismember(data.toBus,data.bus))

    error('Invalid To bus found in Line_Data.');

end


% Check line resistance/reactance

if any(data.Rline == 0 & data.Xline == 0)

    error('A line has both R and X equal to zero.');

end


% Check line status

if any(data.lineStatus ~= 0 & data.lineStatus ~= 1)

    error('Line Status must be 0 or 1.');

end


%% ------------------------------------------------------------
% 3. TRANSFORMER TAP
% ------------------------------------------------------------

% In the Excel file a tap value of 0 means unity tap.
% Therefore change 0 to 1.

for i = 1:length(data.tap)

    if data.tap(i) == 0

        data.tap(i) = 1;

    end

end


% Negative tap is not allowed

if any(data.tap < 0)

    error('Transformer tap cannot be negative.');

end


%% ------------------------------------------------------------
% 4. READ GENERATOR DATA
% ------------------------------------------------------------

genTable = readtable(filename,'Sheet','Generator_Data');

data.genID = genTable.Gen_ID;
data.genBus = genTable.Bus;

data.Pg_MW = genTable.Pg_MW;
data.Qg_Mvar = genTable.Qg_Mvar;

data.Pmax_MW = genTable.Pmax_MW;
data.Pmin_MW = genTable.Pmin_MW;

data.Qmax_Mvar = genTable.Qmax_Mvar;
data.Qmin_Mvar = genTable.Qmin_Mvar;

data.Vg = genTable.Vg_pu;

data.machineRating = genTable.mBase_MVA;

data.genStatus = genTable.Status;

data.Hgen = genTable.H_s;
data.Dgen = genTable.D;

% Ra_pu is used as generator droop in this project

data.governor = genTable.Ra_pu;

data.Xd1 = genTable.Xd1_pu;
data.Xq1 = genTable.Xq1_pu;

data.Xd = genTable.Xd_pu;
data.Xq = genTable.Xq_pu;

data.Tdo1 = genTable.Tdo1_s;
data.Tqo1 = genTable.Tqo1_s;

data.Xl = genTable.Xl_pu;

data.freq = genTable.freq;


% Convert everything to column vectors

data.genID = data.genID(:);
data.genBus = data.genBus(:);

data.Pg_MW = data.Pg_MW(:);
data.Qg_Mvar = data.Qg_Mvar(:);

data.Pmax_MW = data.Pmax_MW(:);
data.Pmin_MW = data.Pmin_MW(:);

data.Qmax_Mvar = data.Qmax_Mvar(:);
data.Qmin_Mvar = data.Qmin_Mvar(:);

data.Vg = data.Vg(:);

data.machineRating = data.machineRating(:);

data.genStatus = data.genStatus(:);

data.Hgen = data.Hgen(:);
data.Dgen = data.Dgen(:);

data.governor = data.governor(:);

data.Xd1 = data.Xd1(:);
data.Xq1 = data.Xq1(:);

data.Xd = data.Xd(:);
data.Xq = data.Xq(:);

data.Tdo1 = data.Tdo1(:);
data.Tqo1 = data.Tqo1(:);

data.Xl = data.Xl(:);

data.freq = data.freq(:);


% Check generator buses

if any(~ismember(data.genBus,data.bus))

    error('Generator bus is not present in Bus_Data.');

end


% Check generator limits

if any(data.Pmin_MW > data.Pmax_MW)

    error('Generator Pmin is greater than Pmax.');

end

if any(data.Qmin_Mvar > data.Qmax_Mvar)

    error('Generator Qmin is greater than Qmax.');

end


%% ------------------------------------------------------------
% 5. FIND SLACK BUS
% ------------------------------------------------------------

slackBus = data.bus(data.busType == 1);

if length(slackBus) == 0

    error('No slack bus found.');

end

if length(slackBus) > 1

    error('More than one slack bus found.');

end


% Find generator at slack bus

data.swingGen = find(data.genBus == slackBus);


if length(data.swingGen) == 0

    error('No generator found at the slack bus.');

end


% If more than one generator is at slack bus,
% use the first one.

if length(data.swingGen) > 1

    data.swingGen = data.swingGen(1);

end


%% ------------------------------------------------------------
% 6. READ REGION DATA
% ------------------------------------------------------------

regionTable = readtable(filename,'Sheet','Region_Data');

data.regionBus = regionTable.Bus;
data.regionID = regionTable.Region_ID;

data.critical = regionTable.Critical;


% Non-shedable bus load
%
% Blank cells in Excel become NaN.
% NaN is changed to zero.

data.nonShedable_MW = ...
    regionTable.Non_shedable_bus;

for i = 1:length(data.nonShedable_MW)

    if isnan(data.nonShedable_MW(i))

        data.nonShedable_MW(i) = 0;

    end

end


data.regionBus = data.regionBus(:);
data.regionID = data.regionID(:);
data.critical = data.critical(:);
data.nonShedable_MW = data.nonShedable_MW(:);


% Check region buses

if any(~ismember(data.bus,data.regionBus))

    error('Some buses are missing from Region_Data.');

end


% Put region information in the same order as Bus_Data

newRegionID = zeros(length(data.bus),1);
newCritical = zeros(length(data.bus),1);
newNonShedable = zeros(length(data.bus),1);

for i = 1:length(data.bus)

    position = find(data.regionBus == data.bus(i));

    if length(position) == 0

        error('Bus not found in Region_Data.');

    end

    newRegionID(i) = data.regionID(position(1));

    newCritical(i) = data.critical(position(1));

    newNonShedable(i) = ...
        data.nonShedable_MW(position(1));

end


data.regionBus = data.bus;

data.regionID = newRegionID;

data.critical = newCritical;

data.nonShedable_MW = newNonShedable;


%% ------------------------------------------------------------
% 7. READ FEEDER DATA
% ------------------------------------------------------------

feederTable = readtable(filename,'Sheet','Feeder_Data');


% Feeder_ID can contain values such as F1, F2, F3.
% Therefore keep it as text.

data.feederID = string(feederTable.Feeder_ID);

data.feederSourceBus = feederTable.Source_Bus;

data.feederLoad_MW = feederTable.Load_MW;

data.feederNonShedable_MW = ...
    feederTable.Non_shedable_feeder;

data.feederStatus = feederTable.Status;


% Convert to column vectors

data.feederID = data.feederID(:);

data.feederSourceBus = ...
    data.feederSourceBus(:);

data.feederLoad_MW = ...
    data.feederLoad_MW(:);

data.feederNonShedable_MW = ...
    data.feederNonShedable_MW(:);

data.feederStatus = ...
    data.feederStatus(:);


% Blank feeder non-shedable values = zero

for i = 1:length(data.feederNonShedable_MW)

    if isnan(data.feederNonShedable_MW(i))

        data.feederNonShedable_MW(i) = 0;

    end

end


% Check feeder source buses

if any(~ismember(data.feederSourceBus,data.bus))

    error('Invalid feeder Source_Bus found.');

end


% Check feeder load

if any(data.feederLoad_MW < 0)

    error('Negative feeder load found.');

end


% Check non-shedable feeder load

if any(data.feederNonShedable_MW < 0)

    error('Negative feeder non-shedable load found.');

end


% Non-shedable feeder load cannot be greater
% than total feeder load

if any(data.feederNonShedable_MW > ...
       data.feederLoad_MW)

    error('Feeder non-shedable load is greater than feeder load.');

end


% Check feeder status

if any(data.feederStatus ~= 0 & ...
       data.feederStatus ~= 1)

    error('Feeder Status must be 0 or 1.');

end


%% ------------------------------------------------------------
% 8. CALCULATE NORMAL SHEDABLE FEEDER LOAD
% ------------------------------------------------------------

data.feederNormalShedable_MW = ...
    data.feederLoad_MW - ...
    data.feederNonShedable_MW;


data.nFeeder = length(data.feederID);


%% ------------------------------------------------------------
% 9. READ UFLS SETTINGS
% ------------------------------------------------------------

uflsTable = readtable(filename,'Sheet','UFLS_Settings');

parameter = string(uflsTable.Parameter);
value = uflsTable.Value;


% Find Base MVA

position = find(parameter == "Base_MVA");

if length(position) == 0

    error('Base_MVA was not found.');

end

data.Sbase = value(position(1));


% Find base frequency

position = find(parameter == "Base_Frequency");

if length(position) == 0

    error('Base_Frequency was not found.');

end

data.f0 = value(position(1));


% Find target frequency

position = find(parameter == "Target_Frequency");

if length(position) == 0

    error('Target_Frequency was not found.');

end

data.fTarget = value(position(1));


% Find UFLS trigger frequency

position = find(parameter == "Trigger_Frequency");

if length(position) == 0

    error('Trigger_Frequency was not found.');

end

data.UFLStrigger = value(position(1));


% Find UFLS delay

position = find(parameter == "Delay");

if length(position) == 0

    error('Delay was not found.');

end

data.UFLSdelay = value(position(1));


% Find load damping

position = find(parameter == "Load_Damping_Percent");

if length(position) == 0

    error('Load_Damping_Percent was not found.');

end

data.loadDampingPercent = value(position(1));


% Find frequency sensitivity

position = find(parameter == "Frequency_Sensitivity_K");

if length(position) == 0

    error('Frequency_Sensitivity_K was not found.');

end

data.frequencySensitivityK = value(position(1));


%% ------------------------------------------------------------
% 10. READ SOLAR DATA
% ------------------------------------------------------------

solarTable = readtable(filename,'Sheet','Solar_Data');

data.solarID = solarTable.Solar_ID;

data.solarBus = solarTable.Bus;

data.Psolar_MW = solarTable.Psolar_MW;


data.solarID = data.solarID(:);
data.solarBus = data.solarBus(:);
data.Psolar_MW = data.Psolar_MW(:);


% Check solar buses

if any(~ismember(data.solarBus,data.bus))

    error('Solar bus is not present in Bus_Data.');

end


% Solar generation cannot be negative

if any(data.Psolar_MW < 0)

    error('Negative solar generation found.');

end


%% ------------------------------------------------------------
% 11. READ SOLAR FACTOR
% ------------------------------------------------------------

solarFactorTable = ...
    readtable(filename,'Sheet','Solar_Factor');


data.solarTime = solarFactorTable.Time;

data.solarGeneration = ...
    solarFactorTable.Solar_Generation_MW;

data.SF = solarFactorTable.Solar_Factor;


% Date is optional

if ismember('Date',solarFactorTable.Properties.VariableNames)

    data.solarDate = solarFactorTable.Date;

else

    data.solarDate = [];

end


data.solarTime = data.solarTime(:);

data.solarGeneration = ...
    data.solarGeneration(:);

data.SF = data.SF(:);


%% ------------------------------------------------------------
% 12. READ LOAD FACTOR
% ------------------------------------------------------------

loadFactorTable = ...
    readtable(filename,'Sheet','Load_Factor');


data.loadTime = loadFactorTable.Time;

data.BD_Demand_MW = ...
    loadFactorTable.BD_Demand_MW;

data.LF = loadFactorTable.Load_Factor;


% Date is optional

if ismember('Date',loadFactorTable.Properties.VariableNames)

    data.loadDate = loadFactorTable.Date;

else

    data.loadDate = [];

end


data.loadTime = data.loadTime(:);

data.BD_Demand_MW = ...
    data.BD_Demand_MW(:);

data.LF = data.LF(:);


%% ------------------------------------------------------------
% 13. CONVERT MW VALUES TO PER UNIT
% ------------------------------------------------------------

data.Psolar0 = ...
    data.Psolar_MW / data.Sbase;

data.Pload0 = ...
    data.Pload_MW / data.Sbase;

data.Qload0 = ...
    data.Qload_Mvar / data.Sbase;

data.Pg0 = ...
    data.Pg_MW / data.Sbase;

data.Qg0 = ...
    data.Qg_Mvar / data.Sbase;

data.Pmax = ...
    data.Pmax_MW / data.Sbase;

data.Pmin = ...
    data.Pmin_MW / data.Sbase;

data.Qmax = ...
    data.Qmax_Mvar / data.Sbase;

data.Qmin = ...
    data.Qmin_Mvar / data.Sbase;


% Feeder per-unit values

data.feederLoad_pu = ...
    data.feederLoad_MW / data.Sbase;

data.feederNonShedable_pu = ...
    data.feederNonShedable_MW / data.Sbase;

data.feederNormalShedable_pu = ...
    data.feederNormalShedable_MW / data.Sbase;


%% ------------------------------------------------------------
% 14. TOTAL LOAD
% ------------------------------------------------------------

data.totalLoad_MW = sum(data.Pload_MW);


%% ------------------------------------------------------------
% 15. DISPLAY INPUT INFORMATION
% ------------------------------------------------------------

fprintf('\n');
fprintf('============================================\n');
fprintf('        MODULE 1 INPUT DATA\n');
fprintf('============================================\n');

fprintf('Number of buses       = %d\n',length(data.bus));

fprintf('Number of lines       = %d\n',length(data.fromBus));

fprintf('Number of generators  = %d\n',length(data.genID));

fprintf('Number of solar units = %d\n',length(data.solarID));

fprintf('Number of feeders     = %d\n',data.nFeeder);

fprintf('Total load            = %.2f MW\n',...
    data.totalLoad_MW);

fprintf('Base MVA              = %.2f MVA\n',...
    data.Sbase);

fprintf('Base frequency        = %.2f Hz\n',...
    data.f0);

fprintf('Target frequency      = %.2f Hz\n',...
    data.fTarget);

fprintf('UFLS trigger          = %.2f Hz\n',...
    data.UFLStrigger);

fprintf('============================================\n');

fprintf('Module 1 completed successfully.\n');
fprintf('============================================\n');

end

