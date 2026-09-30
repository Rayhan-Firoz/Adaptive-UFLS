function op = updateOpCondAtHour(data,testHour)
%==========================================================================
% UPDATE OPERATING CONDITION AT A SPECIFIED HOUR
%
% PURPOSE
%   This is a TEST/STUDY helper for Module 13 and later studies.
%
%   It performs the same operating-condition calculation as Module 2,
%   but instead of using the computer's current time, the user provides
%   the required hour.
%
% EXAMPLE:
%
%   op = updateOpCondAtHour(data,12);
%
%   This represents 12:00 noon.
%
% IMPORTANT
%   This function does NOT replace Module 2.
%
%   Module 2:
%       two_updateOpCond(data)
%
%   uses the actual computer clock.
%
%   This helper:
%       updateOpCondAtHour(data,testHour)
%
%   uses a fixed test hour.
%
%==========================================================================


%% ========================================================================
% 1. CHECK INPUT
% =========================================================================

if nargin < 2 || isempty(testHour)

    testHour = 12;

end


if ~isscalar(testHour) || ...
        ~isfinite(testHour) || ...
        testHour < 0 || ...
        testHour > 24

    error( ...
        'updateOpCondAtHour: testHour must be between 0 and 24.');

end


%% ========================================================================
% 2. CONVERT LOAD TIME TO DECIMAL HOURS
% =========================================================================

loadTime = datetime( ...
    string(data.loadTime), ...
    'InputFormat','HH:mm');


loadHour = ...
    hour(loadTime) + ...
    minute(loadTime)/60;


%% ========================================================================
% 3. CONVERT SOLAR TIME TO DECIMAL HOURS
% =========================================================================

solarTime = datetime( ...
    string(data.solarTime), ...
    'InputFormat','HH:mm');


solarHour = ...
    hour(solarTime) + ...
    minute(solarTime)/60;


%% ========================================================================
% 4. REMOVE INVALID LOAD DATA
% =========================================================================

validLoad = ...
    ~isnan(loadHour) & ...
    ~isnan(data.LF);


loadHour = ...
    loadHour(validLoad);


LF = ...
    data.LF(validLoad);


%% ========================================================================
% 5. REMOVE INVALID SOLAR DATA
% =========================================================================

validSolar = ...
    ~isnan(solarHour) & ...
    ~isnan(data.SF);


solarHour = ...
    solarHour(validSolar);


SF = ...
    data.SF(validSolar);


%% ========================================================================
% 6. SORT LOAD TIME DATA
% =========================================================================

[loadHour,loadIndex] = ...
    sort(loadHour);


LF = ...
    LF(loadIndex);


%% ========================================================================
% 7. SORT SOLAR TIME DATA
% =========================================================================

[solarHour,solarIndex] = ...
    sort(solarHour);


SF = ...
    SF(solarIndex);


%% ========================================================================
% 8. FIND LOAD FACTOR AT TEST HOUR
% =========================================================================

LF_current = ...
    interp1( ...
    loadHour, ...
    LF, ...
    testHour, ...
    'linear', ...
    'extrap');


%% ========================================================================
% 9. FIND SOLAR FACTOR AT TEST HOUR
% =========================================================================

SF_current = ...
    interp1( ...
    solarHour, ...
    SF, ...
    testHour, ...
    'linear', ...
    'extrap');


%% ========================================================================
% 10. UPDATE BUS LOAD
% =========================================================================
%
% Pload(t) = Pload0 x LF
%
% Qload(t) = Qload0 x LF
%
% Pload and Qload are in pu.
%
% This is the same calculation used by Module 2.
% ========================================================================

op.Pload = ...
    data.Pload0 * LF_current;


op.Qload = ...
    data.Qload0 * LF_current;


%% ========================================================================
% 11. STORE CRITICAL BUS INFORMATION
% =========================================================================

op.critical = ...
    data.critical;


%% ========================================================================
% 12. UPDATE BUS-LEVEL NON-SHEDABLE LOAD
% =========================================================================
%
% Current non-shedable bus load =
%
%       Base non-shedable load x LF
%
% Module 2 performs the same scaling.
% ========================================================================

op.nonShedable_MW = ...
    data.nonShedable_MW * LF_current;


%% ========================================================================
% 13. UPDATE TOTAL FEEDER LOAD
% =========================================================================

op.feederLoad_MW = ...
    data.feederLoad_MW * LF_current;


%% ========================================================================
% 14. UPDATE FEEDER NON-SHEDABLE LOAD
% =========================================================================

op.feederNonShedable_MW = ...
    data.feederNonShedable_MW * LF_current;


%% ========================================================================
% 15. UPDATE FEEDER NORMAL-SHEDABLE LOAD
% =========================================================================

op.feederNormalShedable_MW = ...
    data.feederNormalShedable_MW * LF_current;


%% ========================================================================
% 16. CHECK FEEDER LOAD DECOMPOSITION
% =========================================================================
%
% Feeder Load =
%       Non-shedable load
%       +
%       Normal shedable load
%
% This is the same consistency check used in Module 2.
% ========================================================================

feederCheck = ...
    op.feederNonShedable_MW + ...
    op.feederNormalShedable_MW;


if any(abs( ...
        feederCheck - ...
        op.feederLoad_MW) > 1e-8)

    error( ...
        ['updateOpCondAtHour: feeder load decomposition is ' ...
         'inconsistent. Check feeder input data.']);

end


%% ========================================================================
% 17. START WITH ORIGINAL SYNCHRONOUS GENERATION
% =========================================================================
%
% Synchronous generation is kept separate from solar generation.
%
% op.Pg and op.Qg contain synchronous generator values.
%
% Solar is stored separately in op.Psolar.
% ========================================================================

op.Pg = ...
    data.Pg0;


op.Qg = ...
    data.Qg0;


%% ========================================================================
% 18. CALCULATE SOLAR GENERATION
% =========================================================================
%
% Psolar(t) =
%       Psolar0 x Solar Factor
%
% Solar remains separate from synchronous generation.
% ========================================================================

op.Psolar = ...
    data.Psolar0 * SF_current;


%% ========================================================================
% 19. STORE SOLAR BUS INFORMATION
% =========================================================================

op.solarBus = ...
    data.solarBus;


%% ========================================================================
% 20. STORE OPERATING CONDITION INFORMATION
% =========================================================================

op.LF = ...
    LF_current;


op.SF = ...
    SF_current;


% Store the selected hour.

op.currentHour = ...
    testHour;


% Create a datetime corresponding to the selected hour.
%
% The actual date is not important for the study.
% The hour is what determines LF and SF.

baseDate = dateshift(datetime('now'),'start','day');

op.currentTime = ...
    baseDate + hours(testHour);


%% ========================================================================
% 21. TOTAL BUS LOAD
% =========================================================================

op.totalLoadP = ...
    sum(op.Pload);


op.totalLoadQ = ...
    sum(op.Qload);


%% ========================================================================
% 22. TOTAL BUS NON-SHEDABLE LOAD
% =========================================================================

op.totalNonShedableBus_MW = ...
    sum(op.nonShedable_MW);


%% ========================================================================
% 23. TOTAL FEEDER LOAD
% =========================================================================

op.totalFeederLoad_MW = ...
    sum(op.feederLoad_MW);


%% ========================================================================
% 24. TOTAL FEEDER NON-SHEDABLE LOAD
% =========================================================================

op.totalFeederNonShedable_MW = ...
    sum(op.feederNonShedable_MW);


%% ========================================================================
% 25. TOTAL FEEDER NORMAL-SHEDABLE LOAD
% =========================================================================

op.totalFeederNormalShedable_MW = ...
    sum(op.feederNormalShedable_MW);


%% ========================================================================
% 26. TOTAL SOLAR GENERATION
% =========================================================================

op.totalSolar = ...
    sum(op.Psolar);


%% ========================================================================
% 27. TOTAL SYNCHRONOUS GENERATION
% =========================================================================

op.totalSynchronousGeneration = ...
    sum(op.Pg);


%% ========================================================================
% 28. TOTAL GENERATION INCLUDING SOLAR
% =========================================================================

op.totalGeneration = ...
    op.totalSynchronousGeneration + ...
    op.totalSolar;


%% ========================================================================
% 29. DISPLAY OPERATING CONDITION
% =========================================================================

fprintf('\n');
fprintf('============================================\n');
fprintf('   OPERATING CONDITION AT SPECIFIED HOUR\n');
fprintf('============================================\n');

fprintf('Test hour                = %05.2f h\n', ...
    testHour);

fprintf('Load Factor              = %.6f\n', ...
    op.LF);

fprintf('Solar Factor             = %.6f\n', ...
    op.SF);

fprintf('\n');

fprintf('Total bus load           = %.4f MW\n', ...
    op.totalLoadP * data.Sbase);

fprintf('Bus non-shedable load    = %.4f MW\n', ...
    op.totalNonShedableBus_MW);

fprintf('Total feeder load        = %.4f MW\n', ...
    op.totalFeederLoad_MW);

fprintf('Feeder non-shedable     = %.4f MW\n', ...
    op.totalFeederNonShedable_MW);

fprintf('Feeder normal shedable  = %.4f MW\n', ...
    op.totalFeederNormalShedable_MW);

fprintf('Solar generation         = %.4f MW\n', ...
    op.totalSolar * data.Sbase);

fprintf('Synchronous generation   = %.4f MW\n', ...
    op.totalSynchronousGeneration * data.Sbase);

fprintf('Total generation         = %.4f MW\n', ...
    op.totalGeneration * data.Sbase);

fprintf('============================================\n');

end