function op = two_updateOpCond(data)

clc

%% ============================================================
% MODULE 2
% UPDATE OPERATING CONDITION
%
% Load Factor  -> changes system load
% Solar Factor -> changes solar generation
%
% All load values are scaled using Load Factor.
%
% Solar generation is kept separate from synchronous generators.
% ============================================================


%% ============================================================
% 1. GET CURRENT TIME
% ============================================================

nowTime = datetime('now');

hourNow = hour(nowTime);

minuteNow = minute(nowTime);

currentHour = hourNow + minuteNow/60;


%% ============================================================
% 2. CONVERT LOAD TIME TO HOURS
% ============================================================

loadTime = string(data.loadTime);

loadHour = zeros(length(loadTime),1);


for i = 1:length(loadTime)

    timeValue = datetime( ...
        loadTime(i), ...
        'InputFormat','HH:mm');

    loadHour(i) = ...
        hour(timeValue) + minute(timeValue)/60;

end


%% ============================================================
% 3. CONVERT SOLAR TIME TO HOURS
% ============================================================

solarTime = string(data.solarTime);

solarHour = zeros(length(solarTime),1);


for i = 1:length(solarTime)

    timeValue = datetime( ...
        solarTime(i), ...
        'InputFormat','HH:mm');

    solarHour(i) = ...
        hour(timeValue) + minute(timeValue)/60;

end


%% ============================================================
% 4. SORT LOAD FACTOR DATA
% ============================================================

[loadHour,loadIndex] = sort(loadHour);

LF = data.LF(loadIndex);


%% ============================================================
% 5. SORT SOLAR FACTOR DATA
% ============================================================

[solarHour,solarIndex] = sort(solarHour);

SF = data.SF(solarIndex);


%% ============================================================
% 6. FIND LOAD FACTOR FOR CURRENT TIME
% ============================================================

LF_current = interp1( ...
    loadHour, ...
    LF, ...
    currentHour, ...
    'linear', ...
    'extrap');


%% ============================================================
% 7. FIND SOLAR FACTOR FOR CURRENT TIME
% ============================================================

SF_current = interp1( ...
    solarHour, ...
    SF, ...
    currentHour, ...
    'linear', ...
    'extrap');


%% ============================================================
% 8. UPDATE BUS LOAD
% ============================================================

% Original load is stored in pu.
%
% Current load =
% Original load x Load Factor

op.Pload = ...
    data.Pload0 * LF_current;

op.Qload = ...
    data.Qload0 * LF_current;


%% ============================================================
% 9. STORE CRITICAL BUS INFORMATION
% ============================================================

op.critical = data.critical;


%% ============================================================
% 10. UPDATE BUS NON-SHEDABLE LOAD
% ============================================================

% Non-shedable bus load is stored in MW.

op.nonShedable_MW = ...
    data.nonShedable_MW * LF_current;


%% ============================================================
% 11. UPDATE FEEDER LOAD
% ============================================================

% Total feeder load

op.feederLoad_MW = ...
    data.feederLoad_MW * LF_current;


% Feeder non-shedable load

op.feederNonShedable_MW = ...
    data.feederNonShedable_MW * LF_current;


% Feeder normal shedable load

op.feederNormalShedable_MW = ...
    data.feederNormalShedable_MW * LF_current;


%% ============================================================
% 12. CHECK FEEDER LOAD
% ============================================================

feederCheck = ...
    op.feederNonShedable_MW + ...
    op.feederNormalShedable_MW;


difference = ...
    feederCheck - op.feederLoad_MW;


if any(abs(difference) > 0.000001)

    error('Module 2: feeder load calculation is not correct.');

end


%% ============================================================
% 13. START WITH ORIGINAL GENERATOR OUTPUT
% ============================================================

% These are synchronous generators only.

op.Pg = data.Pg0;

op.Qg = data.Qg0;


%% ============================================================
% 14. UPDATE SYNCHRONOUS GENERATION
% ============================================================

for g = 1:length(op.Pg)

    % Do not change the swing generator here.

    if g ~= data.swingGen

        op.Pg(g) = ...
            data.Pg0(g) * LF_current;


        % Check upper generator limit

        if op.Pg(g) > data.Pmax(g)

            op.Pg(g) = data.Pmax(g);

        end


        % Check lower generator limit

        if op.Pg(g) < data.Pmin(g)

            op.Pg(g) = data.Pmin(g);

        end

    end

end


%% ============================================================
% 15. UPDATE SOLAR GENERATION
% ============================================================

% Solar generation is separate from synchronous generation.
%
% Solar generation =
% Original solar generation x Solar Factor

op.Psolar = ...
    data.Psolar0 * SF_current;


%% ============================================================
% 16. STORE SOLAR BUS NUMBERS
% ============================================================

op.solarBus = data.solarBus;


%% ============================================================
% 17. STORE CURRENT OPERATING CONDITION
% ============================================================

op.LF = LF_current;

op.SF = SF_current;

op.currentTime = nowTime;

op.currentHour = currentHour;


%% ============================================================
% 18. TOTAL BUS ACTIVE POWER LOAD
% ============================================================

op.totalLoadP = sum(op.Pload);


%% ============================================================
% 19. TOTAL BUS REACTIVE POWER LOAD
% ============================================================

op.totalLoadQ = sum(op.Qload);


%% ============================================================
% 20. TOTAL BUS NON-SHEDABLE LOAD
% ============================================================

op.totalNonShedableBus_MW = ...
    sum(op.nonShedable_MW);


%% ============================================================
% 21. TOTAL FEEDER LOAD
% ============================================================

op.totalFeederLoad_MW = ...
    sum(op.feederLoad_MW);


%% ============================================================
% 22. TOTAL FEEDER NON-SHEDABLE LOAD
% ============================================================

op.totalFeederNonShedable_MW = ...
    sum(op.feederNonShedable_MW);


%% ============================================================
% 23. TOTAL FEEDER NORMAL SHEDABLE LOAD
% ============================================================

op.totalFeederNormalShedable_MW = ...
    sum(op.feederNormalShedable_MW);


%% ============================================================
% 24. TOTAL SOLAR GENERATION
% ============================================================

op.totalSolar = ...
    sum(op.Psolar);


%% ============================================================
% 25. TOTAL SYNCHRONOUS GENERATION
% ============================================================

op.totalSynchronousGeneration = ...
    sum(op.Pg);


%% ============================================================
% 26. TOTAL GENERATION INCLUDING SOLAR
% ============================================================

op.totalGeneration = ...
    op.totalSynchronousGeneration + ...
    op.totalSolar;


%% ============================================================
% 27. DISPLAY OPERATING CONDITION
% ============================================================

fprintf('\n');
fprintf('============================================\n');
fprintf('       MODULE 2 OPERATING CONDITION\n');
fprintf('============================================\n');


fprintf('Current time            = %02d:%02d\n', ...
    hourNow,minuteNow);


fprintf('Load Factor             = %.6f\n', ...
    op.LF);


fprintf('Solar Factor            = %.6f\n', ...
    op.SF);


fprintf('\n');


%% ------------------------------------------------------------
% BUS LOAD
% ------------------------------------------------------------

fprintf('BUS LOAD\n');
fprintf('--------------------------------------------\n');


fprintf('Total bus load          = %.4f MW\n', ...
    op.totalLoadP * data.Sbase);


fprintf('Bus non-shedable load   = %.4f MW\n', ...
    op.totalNonShedableBus_MW);


busNormalShedable = ...
    op.totalLoadP * data.Sbase - ...
    op.totalNonShedableBus_MW;


fprintf('Bus normal shedable     = %.4f MW\n', ...
    busNormalShedable);


fprintf('\n');


%% ------------------------------------------------------------
% FEEDER LOAD
% ------------------------------------------------------------

fprintf('FEEDER LOAD\n');
fprintf('--------------------------------------------\n');


fprintf('Feeder total load       = %.4f MW\n', ...
    op.totalFeederLoad_MW);


fprintf('Feeder non-shedable     = %.4f MW\n', ...
    op.totalFeederNonShedable_MW);


fprintf('Feeder normal shedable  = %.4f MW\n', ...
    op.totalFeederNormalShedable_MW);


fprintf('\n');


%% ------------------------------------------------------------
% GENERATION
% ------------------------------------------------------------

fprintf('GENERATION\n');
fprintf('--------------------------------------------\n');


fprintf('Synchronous generation = %.4f MW\n', ...
    op.totalSynchronousGeneration * data.Sbase);


fprintf('Solar generation        = %.4f MW\n', ...
    op.totalSolar * data.Sbase);


fprintf('Total generation        = %.4f MW\n', ...
    op.totalGeneration * data.Sbase);


fprintf('============================================\n');


end
