function post = ten_applyFeederShedding(data, op, result, Ybus, feeder)

%% ============================================================
% MODULE 10: APPLY FEEDER SHEDDING
%
% Module 9 decides which feeders are shed.
% Module 10 applies exactly that shedding.
%
% Normal feeder:
%   0 MW OR complete normal-shedable MW
%
% Critical feeder:
%   0 MW OR complete non-shedable MW
%% ============================================================


%% 1. BASIC INFORMATION

nBus = length(data.bus);
nGen = length(data.genBus);
Sbase = data.Sbase;


%% 2. CHECK INPUTS

if ~isfield(op,'Pload')
    error('Module 10: op.Pload is missing.');
end

if ~isfield(op,'Qload')
    error('Module 10: op.Qload is missing.');
end

if ~isfield(result,'Pg')
    error('Module 10: result.Pg is missing.');
end

if ~isfield(feeder,'sourceBus')
    error('Module 10: feeder.sourceBus is missing.');
end

if ~isfield(feeder,'Pshed_MW')
    error('Module 10: feeder.Pshed_MW is missing.');
end


%% 3. FEEDER SHEDDING DATA

sourceBus = feeder.sourceBus(:);
Pshed_MW = feeder.Pshed_MW(:);

nFeeder = length(sourceBus);


% Normal and critical amounts from Module 9

if isfield(feeder,'PshedNormal_MW')

    PshedNormal_MW = ...
        feeder.PshedNormal_MW(:);

else

    PshedNormal_MW = zeros(nFeeder,1);

end


if isfield(feeder,'PshedEmergency_MW')

    PshedCritical_MW = ...
        feeder.PshedEmergency_MW(:);

else

    PshedCritical_MW = zeros(nFeeder,1);

end


%% 4. CHECK FEEDER DATA

if length(Pshed_MW) ~= nFeeder
    error('Module 10: feeder shedding length mismatch.');
end

if length(PshedNormal_MW) ~= nFeeder
    error('Module 10: normal shedding length mismatch.');
end

if length(PshedCritical_MW) ~= nFeeder
    error('Module 10: critical shedding length mismatch.');
end


% Check that Module 9 total is correct

for k = 1:nFeeder

    totalCheck = ...
        PshedNormal_MW(k) + ...
        PshedCritical_MW(k);

    if abs(totalCheck - Pshed_MW(k)) > 1e-6

        error( ...
            ['Module 10: feeder %d shedding mismatch. ' ...
             'Normal + Critical does not equal Total.'], ...
            k);

    end

end


%% 5. INITIALIZE BUS SHEDDING

busNormalShed_MW = zeros(nBus,1);

busCriticalShed_MW = zeros(nBus,1);

busShed_MW = zeros(nBus,1);


%% 6. APPLY NORMAL FEEDER SHEDDING
%
% Whole feeder only.
% No partial feeder shedding.

for k = 1:nFeeder

    shedMW = PshedNormal_MW(k);

    if shedMW <= 1e-10
        continue;
    end

    b = find(data.bus == sourceBus(k),1);

    if isempty(b)

        error( ...
            'Module 10: source bus %d not found.', ...
            sourceBus(k));

    end

    busNormalShed_MW(b) = ...
        busNormalShed_MW(b) + shedMW;

end


%% 7. APPLY CRITICAL FEEDER SHEDDING
%
% Whole critical feeder block only.
%
% IMPORTANT:
% Do not add critical shedding a second time.

for k = 1:nFeeder

    shedMW = PshedCritical_MW(k);

    if shedMW <= 1e-10
        continue;
    end

    b = find(data.bus == sourceBus(k),1);

    if isempty(b)

        error( ...
            'Module 10: critical source bus %d not found.', ...
            sourceBus(k));

    end

    busCriticalShed_MW(b) = ...
        busCriticalShed_MW(b) + shedMW;

end


%% 8. TOTAL BUS SHEDDING

busShed_MW = ...
    busNormalShed_MW + ...
    busCriticalShed_MW;


%% 9. CHECK SHEDDING DOES NOT EXCEED LOAD

currentLoad_MW = ...
    op.Pload(:) * Sbase;


for i = 1:nBus

    if busShed_MW(i) > currentLoad_MW(i) + 1e-6

        error( ...
            ['Module 10: Bus %d shedding %.4f MW ' ...
             'is greater than its load %.4f MW.'], ...
            data.bus(i), ...
            busShed_MW(i), ...
            currentLoad_MW(i));

    end

end


%% 10. TOTAL SHEDDING

totalNormalShed_MW = ...
    sum(PshedNormal_MW);

totalCriticalShed_MW = ...
    sum(PshedCritical_MW);

totalShed_MW = ...
    totalNormalShed_MW + ...
    totalCriticalShed_MW;


%% 11. CHECK BUS AND FEEDER TOTALS

if abs(sum(busNormalShed_MW) - totalNormalShed_MW) > 1e-6

    error('Module 10: normal feeder-to-bus mismatch.');

end


if abs(sum(busCriticalShed_MW) - totalCriticalShed_MW) > 1e-6

    error('Module 10: critical feeder-to-bus mismatch.');

end


if abs(sum(busShed_MW) - totalShed_MW) > 1e-6

    error('Module 10: total feeder-to-bus mismatch.');

end


%% 12. MODULE 8 REQUIREMENT

if isfield(feeder,'module8Required_MW')

    requiredShed_MW = ...
        feeder.module8Required_MW;

else

    requiredShed_MW = totalShed_MW;

end

allocationError_MW = ...
    totalShed_MW - requiredShed_MW;


%% 13. SAVE PRE-TRIP GENERATOR OUTPUT

Pg_pre = result.Pg(:);

if isfield(result,'Qg')

    Qg_pre = result.Qg(:);

elseif isfield(op,'Qg')

    Qg_pre = op.Qg(:);

else

    Qg_pre = zeros(nGen,1);

end


if length(Pg_pre) ~= nGen
    error('Module 10: Pg length mismatch.');
end

if length(Qg_pre) ~= nGen
    error('Module 10: Qg length mismatch.');
end


%% 14. CREATE POST-UFLS OPERATING CONDITION

opPost = op;


% Reduce active load

opPost.Pload = ...
    op.Pload(:) - busShed_MW/Sbase;

opPost.Pload = ...
    max(opPost.Pload,0);


% Reduce reactive load using the same P/Q ratio

for i = 1:nBus

    if op.Pload(i) > 1e-12

        ratio = ...
            opPost.Pload(i)/op.Pload(i);

        ratio = ...
            min(max(ratio,0),1);

        opPost.Qload(i) = ...
            op.Qload(i)*ratio;

    end

end


%% 15. UPDATE TOTAL LOAD

opPost.totalLoadP = ...
    sum(opPost.Pload);

opPost.totalLoadQ = ...
    sum(opPost.Qload);


%% 16. SAVE GENERATOR CONTINGENCY

if ~isfield(op,'tripGen')

    error('Module 10: op.tripGen is missing.');

end

tripGen = round(op.tripGen);

if tripGen < 1 || tripGen > nGen

    error('Module 10: invalid tripGen.');

end

opPost.tripGen = tripGen;


%% 17. CHECK ACTUAL LOAD REDUCTION

loadBefore_MW = ...
    sum(op.Pload)*Sbase;

loadAfter_MW = ...
    sum(opPost.Pload)*Sbase;

actualReduction_MW = ...
    loadBefore_MW - loadAfter_MW;

consistencyError_MW = ...
    actualReduction_MW - totalShed_MW;


if abs(consistencyError_MW) > 1e-6

    error( ...
        ['Module 10: actual load reduction does not equal ' ...
         'feeder shedding.']);

end


%% 18. POST-UFLS NEWTON-RAPHSON

resultPost = ...
    four_newtonRaphson( ...
        data, ...
        opPost, ...
        Ybus);


%% 19. SAVE RESULTS

post.op = opPost;
post.opPost = opPost;

post.result = resultPost;
post.resultPost = resultPost;

post.Ybus = Ybus;

post.Pg_pre = Pg_pre;
post.Qg_pre = Qg_pre;

post.resultPost.Pg_pre = Pg_pre;
post.resultPost.Qg_pre = Qg_pre;


%% 20. SAVE BUS SHEDDING

post.busNormalFeederShed_MW = ...
    busNormalShed_MW;

post.busCriticalShed_MW = ...
    busCriticalShed_MW;

post.busShed_MW = ...
    busShed_MW;


%% 21. SAVE FEEDER SHEDDING

post.feederNormalShed_MW = ...
    PshedNormal_MW;

post.feederCriticalShed_MW = ...
    PshedCritical_MW;

post.feederTotalShed_MW = ...
    Pshed_MW;


%% 22. SAVE TOTALS

post.totalNormalFeederShed_MW = ...
    totalNormalShed_MW;

post.totalCriticalFeederShed_MW = ...
    totalCriticalShed_MW;

post.totalShed_MW = ...
    totalShed_MW;

post.requiredShed_MW = ...
    requiredShed_MW;

post.allocationError_MW = ...
    allocationError_MW;

post.loadBefore_MW = ...
    loadBefore_MW;

post.loadAfter_MW = ...
    loadAfter_MW;

post.actualLoadReduction_MW = ...
    actualReduction_MW;

post.consistencyError_MW = ...
    consistencyError_MW;


%% 23. DISPLAY

fprintf('\n');
fprintf('============================================\n');
fprintf('       MODULE 10: APPLY FEEDER SHEDDING\n');
fprintf('============================================\n');

fprintf('\n');

fprintf('Required shedding       = %.4f MW\n', ...
    requiredShed_MW);

fprintf('Normal feeder shedding  = %.4f MW\n', ...
    totalNormalShed_MW);

fprintf('Critical feeder shedding= %.4f MW\n', ...
    totalCriticalShed_MW);

fprintf('Total applied shedding  = %.4f MW\n', ...
    totalShed_MW);

fprintf('Allocation error         = %.6f MW\n', ...
    allocationError_MW);


%% BUS SUMMARY

fprintf('\n');
fprintf('BUS SHEDDING\n');
fprintf('---------------------------------------------\n');
fprintf('Bus     Normal MW    Critical MW    Total MW\n');
fprintf('---------------------------------------------\n');

for i = 1:nBus

    if busShed_MW(i) > 1e-8

        fprintf( ...
            '%3d     %10.3f    %10.3f    %10.3f\n', ...
            data.bus(i), ...
            busNormalShed_MW(i), ...
            busCriticalShed_MW(i), ...
            busShed_MW(i));

    end

end

fprintf('---------------------------------------------\n');


%% LOAD CHECK

fprintf('\n');
fprintf('LOAD CHECK\n');
fprintf('---------------------------------------------\n');

fprintf('Load before UFLS = %.4f MW\n', ...
    loadBefore_MW);

fprintf('Load after UFLS  = %.4f MW\n', ...
    loadAfter_MW);

fprintf('Actual reduction = %.4f MW\n', ...
    actualReduction_MW);

fprintf('Consistency error= %.6f MW\n', ...
    consistencyError_MW);


fprintf('\n');
fprintf('Post-UFLS NR = COMPLETED\n');
fprintf('Next module  = MODULE 11\n');
fprintf('============================================\n');

end