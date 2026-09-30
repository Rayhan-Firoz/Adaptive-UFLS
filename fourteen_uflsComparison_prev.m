function comparison = fourteen_uflsComparison(filename,testHour,tripGen)
%==========================================================================
% MODULE 14
% THREE-STAGE CONVENTIONAL UFLS vs ADAPTIVE UFLS
%
% Conventional UFLS:
%   Stage 1: f < 49.0 Hz -> 10% fixed load block
%   Stage 2: if target 49.5 Hz is not recovered after Stage 1
%            -> additional 5% fixed load block
%   Stage 3: if target 49.5 Hz is not recovered after Stage 2
%            -> additional 10% fixed load block
%
% The conventional scheme is simulated dynamically.
% Stage 1 is frequency-triggered. After each shedding action, the
% frequency is observed for a recovery-check window. If the target
% frequency is not reached during that window, the next fixed stage is
% applied. Each stage uses the same UFLS relay delay before shedding.
%
% Adaptive UFLS:
%   Existing Modules 6-11 are used unchanged.
%
% The comparison uses the same operating condition and generator trip.
%
% Default:
%   testHour = 12
%   tripGen  = 9
%
% NOTE:
%   This module does NOT modify Modules 6-11.
%==========================================================================

if nargin < 1 || isempty(filename)
    filename = 'IEEE39_UFLS_Master_Input.xlsx';
end
if nargin < 2 || isempty(testHour)
    testHour = 12;
end
if nargin < 3 || isempty(tripGen)
    tripGen = 9;
end

data = one_readInputData(filename);

if tripGen < 3 || tripGen > length(data.genBus)
    error('Module 14: tripGen must be between Gen 3 and Gen %d.', ...
        length(data.genBus));
end

tripGen = round(tripGen);

fprintf('\n============================================================\n');
fprintf(' MODULE 14: THREE-STAGE CONVENTIONAL vs ADAPTIVE UFLS\n');
fprintf('============================================================\n');
fprintf('Operating hour = %02d:00\n',round(testHour));
fprintf('Generator trip = Gen %d / Bus %d\n', ...
    tripGen,data.genBus(tripGen));

%% ========================================================================
% 1. COMMON OPERATING POINT
% =========================================================================

op = updateOpCondAtHourLocal(data,testHour);
op.tripGen = tripGen;

Ybus = three_Ybus(data);

result = four_newtonRaphson(data,op,Ybus);

if isfield(result,'converged') && ~result.converged
    error('Module 14: pre-contingency Newton-Raphson did not converge.');
end

%% ========================================================================
% 2. ADAPTIVE UFLS
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' ADAPTIVE UFLS CASE\n');
fprintf('============================================================\n');

freqAdaptive = five_frequencyResponse( ...
    data,op,result,Ybus,false);

uflsAdaptive = six_requiredLoadShedding( ...
    data,op,result,tripGen);

zoneAdaptive = seven_zoneAllocation( ...
    data,freqAdaptive,uflsAdaptive);

[busAdaptive,zoneAdaptive] = ...
    eight_BusAllocation( ...
        data,op,result,zoneAdaptive);

feederAdaptive = nine_feederAllocation( ...
    data,op,Ybus,busAdaptive,freqAdaptive);

postAdaptive = ten_applyFeederShedding( ...
    data,op,result,Ybus,feederAdaptive);

adaptive = eleven_frequencyExcursion( ...
    data,op,result,postAdaptive);

%% ========================================================================
% 3. THREE-STAGE CONVENTIONAL UFLS
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' THREE-STAGE CONVENTIONAL UFLS CASE\n');
fprintf('============================================================\n');

conventional = runConventionalThreeStage( ...
    data,op,result,Ybus,tripGen);

%% ========================================================================
% 4. COMPARISON RESULTS
% =========================================================================

comparison = struct();

comparison.filename = filename;
comparison.testHour = testHour;
comparison.tripGen = tripGen;
comparison.tripBus = data.genBus(tripGen);

comparison.conventional = conventional.summary;
comparison.adaptive = struct();

comparison.adaptive.requiredShed_MW = ...
    uflsAdaptive.requiredShed_MW;

comparison.adaptive.actualShed_MW = ...
    postAdaptive.actualLoadReduction_MW;

comparison.adaptive.nadir_Hz = ...
    adaptive.minimumFrequency;

comparison.adaptive.finalFrequency_Hz = ...
    adaptive.finalFrequency;

comparison.adaptive.initialROCOF_HzPerS = ...
    adaptive.initialROCOFEstimate;

comparison.adaptive.triggerTime_s = ...
    adaptive.triggerTime;

comparison.adaptive.sheddingTime_s = ...
    adaptive.sheddingTime;

comparison.adaptive.finalSlope_HzPerS = ...
    adaptive.finalSlope;

comparison.adaptive.nadirSecure = ...
    adaptive.nadirSecure;

comparison.adaptive.finalRecovered = ...
    adaptive.finalRecovered;

comparison.adaptive.fullyStabilized = ...
    adaptive.fullyStabilized;

comparison.adaptive.result11 = adaptive;
comparison.adaptive.feeder = feederAdaptive;

comparison.conventional.result = conventional.result;
comparison.conventional.feederStage = conventional.feederStage;

%% ========================================================================
% 5. PRINT FINAL COMPARISON
% =========================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' MODULE 14 FINAL COMPARISON\n');
fprintf('============================================================\n');

fprintf('\n');
fprintf('Parameter                    Conventional       Adaptive\n');
fprintf('------------------------------------------------------------\n');

fprintf('Total required shed (MW)       %12.4f     %12.4f\n', ...
    conventional.summary.requiredShed_MW, ...
    comparison.adaptive.requiredShed_MW);

fprintf('Total actual shed (MW)         %12.4f     %12.4f\n', ...
    conventional.summary.actualShed_MW, ...
    comparison.adaptive.actualShed_MW);

fprintf('Frequency nadir (Hz)           %12.4f     %12.4f\n', ...
    conventional.summary.nadir_Hz, ...
    comparison.adaptive.nadir_Hz);

fprintf('Final frequency (Hz)           %12.4f     %12.4f\n', ...
    conventional.summary.finalFrequency_Hz, ...
    comparison.adaptive.finalFrequency_Hz);

fprintf('Initial ROCOF (Hz/s)           %12.4f     %12.4f\n', ...
    conventional.summary.initialROCOF_HzPerS, ...
    comparison.adaptive.initialROCOF_HzPerS);

fprintf('Final slope (Hz/s)             %12.6f     %12.6f\n', ...
    conventional.summary.finalSlope_HzPerS, ...
    comparison.adaptive.finalSlope_HzPerS);

fprintf('Nadir secure                   %12s     %12s\n', ...
    yesNo(conventional.summary.nadirSecure), ...
    yesNo(comparison.adaptive.nadirSecure));

fprintf('Final recovered                %12s     %12s\n', ...
    yesNo(conventional.summary.finalRecovered), ...
    yesNo(comparison.adaptive.finalRecovered));

fprintf('Fully stabilized               %12s     %12s\n', ...
    yesNo(conventional.summary.fullyStabilized), ...
    yesNo(comparison.adaptive.fullyStabilized));

fprintf('============================================================\n');

fprintf('\nCONVENTIONAL UFLS STAGES\n');
fprintf('------------------------------------------------------------\n');
fprintf('Stage   Trigger/Decision   Shed (MW)   Shed Time (s)\n');
fprintf('------------------------------------------------------------\n');

for k = 1:3
    fprintf('%3d       %10.4f      %10.3f      %10.4f\n', ...
        k, ...
        conventional.triggerTime_s(k), ...
        conventional.stageShed_MW(k), ...
        conventional.sheddingTime_s(k));
end

fprintf('Recovery check window = %.2f s\n', ...
    conventional.recoveryCheckTime_s);
fprintf('Target frequency      = %.3f Hz\n', ...
    conventional.targetFrequency_Hz);

fprintf('------------------------------------------------------------\n');

fprintf('\nConventional selected feeders by stage:\n');
for k = 1:3
    fprintf('  Stage %d: ',k);

    % A stage that was not triggered has no feeder-allocation structure.
    if k <= numel(conventional.feederStage) && ...
            ~isempty(conventional.feederStage{k}) && ...
            isstruct(conventional.feederStage{k}) && ...
            isfield(conventional.feederStage{k},'shedFeederIndex')

        disp(conventional.feederStage{k}.shedFeederIndex(:)');

    else
        fprintf('None (stage not triggered)\n');
    end
end

fprintf('\nAdaptive selected feeders:\n');
disp(feederAdaptive.shedFeederIndex(:)');

%% ========================================================================
% 6. GRAPHS
% =========================================================================

%----------------------------------------------------------------------
% GRAPH 1: COI FREQUENCY COMPARISON
%----------------------------------------------------------------------

% figure( ...
%     'Name','Conventional vs Adaptive UFLS - COI Frequency', ...
%     'NumberTitle','off');
% 
% plot( ...
%     conventional.result.time, ...
%     conventional.result.fCOI, ...
%     'LineWidth',1.6);
% 
% hold on;
% 
% % Keep the frequency comparison focused on the disturbance range.
% ylim([47 50.2]);
% 
% plot( ...
%     adaptive.time, ...
%     adaptive.fCOI, ...
%     'LineWidth',1.6);
% 
% yline( ...
%     data.fTarget(1), ...
%     '--', ...
%     'Target', ...
%     'LineWidth',1.0);
% 
% yline( ...
%     49.5, ...
%     ':', ...
%     '49.5 Hz', ...
%     'LineWidth',1.0);
% 
% yline( ...
%     49.0, ...
%     ':', ...
%     '49.0 Hz', ...
%     'LineWidth',1.0);
% 
% yline( ...
%     48.5, ...
%     ':', ...
%     '48.5 Hz', ...
%     'LineWidth',1.0);
% 
% grid on;
% 
% xlabel('Time (s)');
% ylabel('COI Frequency (Hz)');
% title(sprintf( ...
%     'Conventional vs Adaptive UFLS - Gen %d / Bus %d', ...
%     tripGen,data.genBus(tripGen)));
% 
% legend( ...
%     'Conventional 3-Stage', ...
%     'Adaptive UFLS', ...
%     'Target', ...
%     'Stage 1: 49.5 Hz', ...
%     'Stage 2: 49.0 Hz', ...
%     'Stage 3: 48.5 Hz', ...
%     'Location','best');
% 
% hold off;


%----------------------------------------------------------------------
% GRAPH 2: CONVENTIONAL 3-STAGE vs ADAPTIVE UFLS
%----------------------------------------------------------------------

figure( ...
    'Name','Conventional 3-Stage vs Adaptive UFLS - COI Frequency', ...
    'NumberTitle','off');

% Conventional frequency
plot( ...
    conventional.result.time, ...
    conventional.result.fCOI, ...
    'r', ...
    'LineWidth',1.8);

hold on;

% Adaptive frequency
plot( ...
    adaptive.time, ...
    adaptive.fCOI, ...
    'b', ...
    'LineWidth',1.8);

% Adaptive target
yline( ...
    data.fTarget(1), ...
    '--k', ...
    'Target 49.5 Hz', ...
    'LineWidth',1.0);

% Conventional Stage 1 trigger threshold
yline( ...
    conventional.thresholds_Hz(1), ...
    ':', ...
    sprintf('Stage 1 trigger: %.1f Hz', ...
    conventional.thresholds_Hz(1)), ...
    'LineWidth',1.0);

% Mark actual shedding times
for k = 1:3

    if ~isnan(conventional.sheddingTime_s(k))

        xline( ...
            conventional.sheddingTime_s(k), ...
            '--r', ...
            sprintf('Stage %d shedding',k), ...
            'LineWidth',1.2);

    end

end

% Mark Stage 1 trigger and Stage 2/3 recovery decisions
for k = 1:3

    if ~isnan(conventional.triggerTime_s(k))

        triggerTime = conventional.triggerTime_s(k);

        [~,idx] = min(abs( ...
            conventional.result.time-triggerTime));

        plot( ...
            conventional.result.time(idx), ...
            conventional.result.fCOI(idx), ...
            'ko', ...
            'MarkerFaceColor','r', ...
            'MarkerSize',6);

    end

end

grid on;
box on;

xlabel('Time (s)');
ylabel('COI Frequency (Hz)');

title(sprintf( ...
    'Three-Stage Conventional vs Adaptive UFLS - Gen %d / Bus %d', ...
    tripGen,data.genBus(tripGen)));

legend( ...
    'Conventional 3-Stage', ...
    'Adaptive UFLS', ...
    'Target 49.5 Hz', ...
    sprintf('Stage 1 trigger: %.1f Hz', ...
    conventional.thresholds_Hz(1)), ...
    'Stage shedding', ...
    'Stage trigger / recovery decision', ...
    'Location','best');

ylim([48.0 50.1]);
xlim([0 max(conventional.result.time)]);

hold off;

%----------------------------------------------------------------------
% GRAPH 3: FREQUENCY NADIR COMPARISON
%----------------------------------------------------------------------

figure( ...
    'Name','Conventional vs Adaptive UFLS - Frequency Nadir', ...
    'NumberTitle','off');

bar([ ...
    conventional.summary.nadir_Hz, ...
    comparison.adaptive.nadir_Hz]);

hold on;

yline( ...
    data.fTarget(1), ...
    '--', ...
    'Target', ...
    'LineWidth',1.0);

grid on;

xticks([1 2]);
xticklabels({'Conventional UFLS','Adaptive UFLS'});

ylabel('Minimum COI Frequency (Hz)');
title(sprintf( ...
    'Frequency Nadir - Gen %d / Bus %d', ...
    tripGen,data.genBus(tripGen)));

hold off;

fprintf('\nThree comparison graphs generated.\n');
fprintf('Module 14 complete.\n');

end


%% ========================================================================
% THREE-STAGE CONVENTIONAL DYNAMIC SIMULATION
% =========================================================================

function conventional = runConventionalThreeStage(data,op,result,Ybus,tripGen)

% Conventional UFLS uses the SAME dynamic equations as Module 11.
% State = [delta; omega]
% Governor = instantaneous static droop
% Simulation = 60 s
%
% NEW CONVENTIONAL DECISION LOGIC:
%
%   Stage 1:
%       Trigger when fCOI falls below 49.0 Hz.
%       Shed 10% of the initial load.
%
%   Stage 2:
%       Wait for the recovery-check window after Stage 1 shedding.
%       If fCOI does NOT reach the target frequency (49.5 Hz),
%       shed an additional 5% of the initial load.
%
%   Stage 3:
%       Wait for the recovery-check window after Stage 2 shedding.
%       If fCOI does NOT reach the target frequency (49.5 Hz),
%       shed an additional 10% of the initial load.
%
% Stage 2 and Stage 3 are therefore NOT triggered by lower
% frequency thresholds. They are triggered by failure to recover
% to the target after the previous shedding action.

Sbase=data.Sbase(1);
f0=data.f0(1);
omega_s=2*pi*f0;

% Only Stage 1 has a frequency trigger.
thresholds=[49.5;NaN;NaN];

% Fixed conventional shedding blocks.
stagePercent=[0.05;0.05;0.1];

simulationTime=60;
UFLSdelay=data.UFLSdelay(1);

% Time allowed after each shedding action to check recovery.
recoveryCheckTime=5.0;

% Target used to decide whether another stage is needed.
targetFrequency=data.fTarget(1);

nGen=length(data.genBus);
activeGen=setdiff((1:nGen).',tripGen);
nActive=length(activeGen);

Hgen=data.Hgen(:);
MVA=data.machineRating(:);
Xd1=data.Xd1(:);
Dgen=data.Dgen(:);
Rgen=data.governor(:);

Hsys=Hgen(activeGen).*MVA(activeGen)./Sbase;
Dactive=Dgen(activeGen);
Ractive=Rgen(activeGen);

GovGainMWHz=MVA(activeGen)./(Ractive.*f0);
GovGainPuHz=GovGainMWHz./Sbase;

PgPre=result.Pg(:);
QgPre=result.Qg(:);
Pm0=PgPre(activeGen);

% Initial E' exactly as in Module 11.
Vpre=result.V(:);
anglePre=result.angle(:);

if max(abs(anglePre))>2*pi
    anglePre=deg2rad(anglePre);
end

Vcomplex=Vpre.*exp(1j*anglePre);
EprimeAll=zeros(nGen,1);

for g=1:nGen

    b=find(data.bus==data.genBus(g),1);

    if isempty(b)
        error('Module 14: generator bus mapping failed for Gen %d.',g);
    end

    Sg=PgPre(g)+1j*QgPre(g);
    Ig=conj(Sg/Vcomplex(b));

    XdSystem=Xd1(g)*Sbase/MVA(g);
    EprimeAll(g)=Vcomplex(b)+1j*XdSystem*Ig;
end

Eactive=EprimeAll(activeGen);

% Pre-UFLS reduced network exactly on Module 11 basis.
YloadPre=buildLoadAdmittanceLocal(data,op,Vpre);

Xd1SystemAll=Xd1*Sbase./MVA;

YredPre=buildReducedNetworkLocal( ...
    Ybus,YloadPre,data.genBus,activeGen,Xd1SystemAll,data);

% Initial post-trip mismatch exactly as Module 11.
PeInitial=real(Eactive.*conj(YredPre*Eactive));
initialMismatch=Pm0-PeInitial;

initialROCOFEstimate= ...
    f0*sum(initialMismatch)/(2*sum(Hsys));

Dpercent=data.loadDampingPercent(1);

preLoadMW=sum(op.Pload)*Sbase;

DloadPreMWHz= ...
    preLoadMW*(Dpercent/100)/(0.01*f0);

fprintf('\nConventional initial ROCOF estimate = %.6f Hz/s\n', ...
    initialROCOFEstimate);

fprintf('Conventional recovery target = %.3f Hz\n', ...
    targetFrequency);

fprintf('Recovery-check window = %.2f s\n', ...
    recoveryCheckTime);

% Initial state.
xCurrent=[angle(Eactive);ones(nActive,1)];
tCurrent=0;

currentYred=YredPre;
currentDloadMWHz=DloadPreMWHz;
currentOp=op;

remainingFeeders=true(data.nFeeder,1);

tAll=[];
xAll=[];

stageShed=zeros(3,1);
triggerTime=nan(3,1);
sheddingTime=nan(3,1);
feederStage=cell(3,1);

targetReachedAfterStage=false(3,1);
recoveryDecisionTime=nan(3,1);

for stage=1:3

    if tCurrent>=simulationTime
        break;
    end

    %--------------------------------------------------------------
    % Stage 1 is frequency-triggered.
    % Stage 2 and Stage 3 are recovery-decision triggered.
    %--------------------------------------------------------------

    if stage==1

        threshold=thresholds(1);

        opts=odeset( ...
            'RelTol',1e-7, ...
            'AbsTol',1e-9, ...
            'Events',@(t,x) conventionalFrequencyEvent( ...
                t,x,f0,Hsys,threshold));

        [t1,x1,te,xe]=ode45( ...
            @(t,x)localStaticDroopSwing( ...
                t,x,currentYred,Eactive,Pm0,Hsys,Dactive, ...
                currentDloadMWHz,GovGainPuHz,f0,Sbase,omega_s), ...
            [tCurrent simulationTime],xCurrent,opts);

        if isempty(tAll)
            idx=1:length(t1);
        else
            idx=2:length(t1);
        end

        if ~isempty(idx)
            tAll=[tAll;t1(idx)]; %#ok<AGROW>
            xAll=[xAll;x1(idx,:)]; %#ok<AGROW>
        end

        if isempty(te)

            fprintf('Conventional Stage 1 was NOT triggered.\n');

            xCurrent=x1(end,:).';
            tCurrent=t1(end);

            break;
        end

        triggerTime(1)=te(1);
        xTrigger=xe(1,:).';

        fprintf('\nConventional Stage 1 trigger:\n');
        fprintf('  Threshold    = %.3f Hz\n',threshold);
        fprintf('  Trigger time = %.6f s\n',triggerTime(1));

    else

        % Previous stage failed the recovery check.
        triggerTime(stage)=tCurrent;
        xTrigger=xCurrent;

        fprintf('\nConventional Stage %d recovery decision:\n',stage);
        fprintf('  Target %.3f Hz was NOT reached after Stage %d.\n', ...
            targetFrequency,stage-1);
        fprintf('  Decision time = %.6f s\n',triggerTime(stage));

    end

    %--------------------------------------------------------------
    % Relay delay
    %--------------------------------------------------------------

    sheddingTime(stage)=triggerTime(stage)+UFLSdelay;

    if sheddingTime(stage)>=simulationTime

        xCurrent=xTrigger;
        tCurrent=triggerTime(stage);

        break;
    end

    [td,xd]=ode45( ...
        @(t,x)localStaticDroopSwing( ...
            t,x,currentYred,Eactive,Pm0,Hsys,Dactive, ...
            currentDloadMWHz,GovGainPuHz,f0,Sbase,omega_s), ...
        [triggerTime(stage) sheddingTime(stage)], ...
        xTrigger, ...
        odeset('RelTol',1e-7,'AbsTol',1e-9));

    if length(td)>1
        tAll=[tAll;td(2:end)]; %#ok<AGROW>
        xAll=[xAll;xd(2:end,:)]; %#ok<AGROW>
    end

    %--------------------------------------------------------------
    % Fixed conventional percentage shedding
    %--------------------------------------------------------------

    targetStageMW=stagePercent(stage)*preLoadMW;

    [selected,actualStageMW,remainingFeeders]= ...
        selectConventionalStageFeeders( ...
            data,currentOp,targetStageMW,remainingFeeders);

    stageShed(stage)=actualStageMW;
    feederStage{stage}=selected;

    fprintf('  Stage %d target = %.6f MW\n', ...
        stage,targetStageMW);

    fprintf('  Stage %d actual = %.6f MW\n', ...
        stage,actualStageMW);

    %--------------------------------------------------------------
    % Apply stage and solve NR
    %--------------------------------------------------------------

    [currentOp,~]=applyConventionalFeeders( ...
        data,currentOp,selected.Pshed_MW);

    currentOp.tripGen=tripGen;

    resultStage=four_newtonRaphson( ...
        data,currentOp,Ybus);

    if isfield(resultStage,'converged') && ...
            ~resultStage.converged

        error( ...
            'Module 14: Stage %d post-shedding NR did not converge.', ...
            stage);
    end

    Vstage=resultStage.V(:);

    YloadStage=buildLoadAdmittanceLocal( ...
        data,currentOp,Vstage);

    currentYred=buildReducedNetworkLocal( ...
        Ybus,YloadStage,data.genBus,activeGen, ...
        Xd1SystemAll,data);

    currentDloadMWHz= ...
        sum(currentOp.Pload)*Sbase*(Dpercent/100)/(0.01*f0);

    % State immediately after shedding.
    xCurrent=xd(end,:).';
    tCurrent=sheddingTime(stage);

    %--------------------------------------------------------------
    % Recovery check
    %--------------------------------------------------------------

    recoveryEnd=min( ...
        tCurrent+recoveryCheckTime, ...
        simulationTime);

    if recoveryEnd>tCurrent

        [tr,xr]=ode45( ...
            @(t,x)localStaticDroopSwing( ...
                t,x,currentYred,Eactive,Pm0,Hsys,Dactive, ...
                currentDloadMWHz,GovGainPuHz,f0,Sbase,omega_s), ...
            [tCurrent recoveryEnd], ...
            xCurrent, ...
            odeset('RelTol',1e-7,'AbsTol',1e-9));

        if isempty(tAll)

            tAll=tr;
            xAll=xr;

        else

            if abs(tr(1)-tAll(end))<1e-12
                tr=tr(2:end);
                xr=xr(2:end,:);
            end

            if ~isempty(tr)
                tAll=[tAll;tr]; %#ok<AGROW>
                xAll=[xAll;xr]; %#ok<AGROW>
            end
        end

        xCurrent=xr(end,:).';
        tCurrent=tr(end);

    else

        tr=tCurrent;
        xr=xCurrent.';
    end

    recoveryDecisionTime(stage)=tCurrent;

    omegaCheck=xr(:,nActive+1:2*nActive);

    fCheck=zeros(size(tr));

    for kk=1:length(tr)
        fCheck(kk)= ...
            f0*sum(Hsys.*omegaCheck(kk,:).')/sum(Hsys);
    end

    maxRecoveryFrequency=max(fCheck);

    targetReachedAfterStage(stage)= ...
        maxRecoveryFrequency>=targetFrequency;

    fprintf('  Recovery check after Stage %d:\n',stage);
    fprintf('    Check window end = %.6f s\n',tCurrent);
    fprintf('    Maximum frequency = %.6f Hz\n', ...
        maxRecoveryFrequency);
    fprintf('    Target frequency  = %.6f Hz\n', ...
        targetFrequency);

    if targetReachedAfterStage(stage)

        fprintf('    Target RECOVERED. No further conventional stage.\n');

        break;

    else

        fprintf('    Target NOT recovered.');

        if stage<3
            fprintf(' Stage %d will be applied.\n',stage+1);
        else
            fprintf(' No further stage is available.\n');
        end
    end

end

%--------------------------------------------------------------
% Continue to the common 60-s endpoint.
%--------------------------------------------------------------

if tCurrent<simulationTime

    [tf,xf]=ode45( ...
        @(t,x)localStaticDroopSwing( ...
            t,x,currentYred,Eactive,Pm0,Hsys,Dactive, ...
            currentDloadMWHz,GovGainPuHz,f0,Sbase,omega_s), ...
        [tCurrent simulationTime], ...
        xCurrent, ...
        odeset('RelTol',1e-7,'AbsTol',1e-9));

    if isempty(tAll)

        tAll=tf;
        xAll=xf;

    else

        if abs(tf(1)-tAll(end))<1e-12
            tf=tf(2:end);
            xf=xf(2:end,:);
        end

        if ~isempty(tf)
            tAll=[tAll;tf];
            xAll=[xAll;xf];
        end
    end
end

if isempty(tAll)
    tAll=0;
    xAll=xCurrent.';
end

%--------------------------------------------------------------
% Frequency calculations
%--------------------------------------------------------------

omegaAll=xAll(:,nActive+1:2*nActive);

fCOI=zeros(size(tAll));

for k=1:length(tAll)
    fCOI(k)= ...
        f0*sum(Hsys.*omegaAll(k,:).')/sum(Hsys);
end

if length(tAll)>=2
    dfdt=gradient(fCOI,tAll);
else
    dfdt=zeros(size(fCOI));
end

initialFrequency=fCOI(1);
initialROCOF=initialROCOFEstimate;

[minFrequency,nadirIndex]=min(fCOI);
nadirTime=tAll(nadirIndex);

finalFrequency=fCOI(end);

nSlope=min(20,length(dfdt));

if nSlope>=2
    finalSlope=mean(dfdt(end-nSlope+1:end));
else
    finalSlope=dfdt(end);
end

nadirSecure=minFrequency>=targetFrequency;
finalRecovered=finalFrequency>=targetFrequency;
fullyStabilized=abs(finalSlope)<=0.01;

%--------------------------------------------------------------
% Output structures
%--------------------------------------------------------------

r.time=tAll;
r.fCOI=fCOI;
r.dfdt=dfdt;
r.freqGen=f0*omegaAll;
r.tripGen=tripGen;

r.minimumFrequency=minFrequency;
r.nadirTime=nadirTime;
r.finalFrequency=finalFrequency;

r.initialFrequency=initialFrequency;
r.initialROCOF=initialROCOF;
r.finalSlope=finalSlope;

r.targetFrequency=targetFrequency;

r.nadirSecure=nadirSecure;
r.finalRecovered=finalRecovered;
r.fullyStabilized=fullyStabilized;

summary.requiredShed_MW=sum(stageShed);
summary.actualShed_MW=sum(stageShed);

summary.nadir_Hz=minFrequency;
summary.finalFrequency_Hz=finalFrequency;

summary.initialROCOF_HzPerS=initialROCOF;
summary.finalSlope_HzPerS=finalSlope;

summary.nadirSecure=nadirSecure;
summary.finalRecovered=finalRecovered;
summary.fullyStabilized=fullyStabilized;

conventional.result=r;
conventional.summary=summary;

conventional.thresholds_Hz=thresholds;
conventional.stageShed_MW=stageShed;

conventional.triggerTime_s=triggerTime;
conventional.sheddingTime_s=sheddingTime;

conventional.recoveryDecisionTime_s= ...
    recoveryDecisionTime;

conventional.targetReachedAfterStage= ...
    targetReachedAfterStage;

conventional.recoveryCheckTime_s= ...
    recoveryCheckTime;

conventional.targetFrequency_Hz= ...
    targetFrequency;

conventional.feederStage=feederStage;

conventional.totalShed_MW=sum(stageShed);

conventional.nStagesTriggered= ...
    sum(~isnan(triggerTime));

end


%% ========================================================================
% SAME STATIC-DROOP SWING EQUATION AS MODULE 11
% =========================================================================
function dx=localStaticDroopSwing( ...
    ~,x,Yred,Eactive,Pm0,Hsys,Dgen,DloadMWHz, ...
    GovGainPuHz,f0,Sbase,omega_s)

nGen=length(Pm0);
delta=x(1:nGen);
omega=x(nGen+1:2*nGen);

E=abs(Eactive).*exp(1j*delta);
I=Yred*E;
Pe=real(E.*conj(I));

omegaCOI=sum(Hsys.*omega)/sum(Hsys);
fCOI=f0*omegaCOI;
deltaF=fCOI-f0;

deltaPgov=-GovGainPuHz.*deltaF;
PmGovernor=Pm0+deltaPgov;

deltaPloadTotalPu=DloadMWHz*deltaF/Sbase;
loadShare=Hsys/sum(Hsys);
deltaPloadIndividual=deltaPloadTotalPu.*loadShare;

deltaPgenDamping=Dgen.*(omega-1);

domega=(PmGovernor-Pe-deltaPgenDamping- ...
    deltaPloadIndividual)./(2*Hsys);

ddelta=omega_s*(omega-1);

dx=[ddelta;domega];
end


%% ========================================================================
% CONVENTIONAL FREQUENCY EVENT
% =========================================================================
function [value,isterminal,direction]= ...
    conventionalFrequencyEvent(~,x,f0,Hsys,threshold)

nGen=length(Hsys);
omega=x(nGen+1:2*nGen);
fCOI=f0*sum(Hsys.*omega)/sum(Hsys);

value=fCOI-threshold;
isterminal=1;
direction=-1;
end


%% ========================================================================
% SELECT WHOLE FEEDERS FOR ONE CONVENTIONAL STAGE
% =========================================================================
function [selected,actualMW,remainingMask] = ...
    selectConventionalStageFeeders( ...
        data,op,targetMW,remainingMask)

nFeeder = data.nFeeder;

selected = struct();
selected.Pshed_MW = zeros(nFeeder,1);

remaining = targetMW;

available = op.feederNormalShedable_MW(:);

% First take whole blocks that do not exceed the stage target.
for k = 1:nFeeder

    if remaining <= 1e-9
        break;
    end

    if ~remainingMask(k)
        continue;
    end

    if data.feederStatus(k) ~= 1
        continue;
    end

    if available(k) <= 1e-9
        continue;
    end

    if available(k) <= remaining + 1e-9

        selected.Pshed_MW(k) = available(k);
        remaining = remaining - available(k);

        remainingMask(k) = false;
    end
end

% Complete the stage with the smallest available whole feeder.
if remaining > 1e-9

    candidates = [];

    for k = 1:nFeeder

        if ~remainingMask(k)
            continue;
        end

        if data.feederStatus(k) ~= 1
            continue;
        end

        if available(k) >= remaining - 1e-9
            candidates(end+1) = k; %#ok<AGROW>
        end
    end

    if ~isempty(candidates)

        [~,ii] = min(available(candidates));
        k = candidates(ii);

        selected.Pshed_MW(k) = available(k);
        remainingMask(k) = false;
    end
end

selected.shedFeederIndex = ...
    find(selected.Pshed_MW > 1e-9);

selected.shedFeederBus = ...
    data.feederSourceBus(selected.shedFeederIndex);

selected.shedFeederMW = ...
    selected.Pshed_MW(selected.shedFeederIndex);

selected.totalShed_MW = ...
    sum(selected.Pshed_MW);

selected.requiredStage_MW = targetMW;
selected.overshed_MW = ...
    max(0,selected.totalShed_MW-targetMW);

selected.partialFeederSheddingAllowed = false;
selected.protectedLoadPreserved = true;

actualMW = selected.totalShed_MW;

end


%% ========================================================================
% APPLY CONVENTIONAL FEEDERS TO OP
% =========================================================================
function [opPost,busShedMW] = ...
    applyConventionalFeeders(data,op,Pshed)

Sbase = data.Sbase;
nBus = length(data.bus);

opPost = op;

busShedMW = zeros(nBus,1);

for k = 1:data.nFeeder

    if Pshed(k) <= 1e-9
        continue;
    end

    b = find(data.bus == data.feederSourceBus(k),1);

    if isempty(b)
        error('Module 14: feeder %d source bus not found.',k);
    end

    busShedMW(b) = busShedMW(b) + Pshed(k);
end

for b = 1:nBus

    shed = busShedMW(b);

    if shed <= 1e-9
        continue;
    end

    currentLoadMW = opPost.Pload(b)*Sbase;

    if shed > currentLoadMW + 1e-8
        error('Module 14: feeder shedding exceeds Bus %d load.', ...
            data.bus(b));
    end

    factor = max(0,1-shed/currentLoadMW);

    opPost.Pload(b) = opPost.Pload(b)*factor;
    opPost.Qload(b) = opPost.Qload(b)*factor;
end

opPost.busShed_MW = busShedMW;
opPost.totalShed_MW = sum(busShedMW);

opPost.feederTripIndex = ...
    find(Pshed > 1e-9);

opPost.feederTripBus = ...
    data.feederSourceBus(opPost.feederTripIndex);

opPost.feederTripMW = ...
    Pshed(opPost.feederTripIndex);

end





%% ========================================================================
% BUILD LOAD ADMITTANCE
% =========================================================================
function Yload = ...
    buildLoadAdmittanceLocal(data,opState,Vmag)

nBus = length(data.bus);
Sbase = data.Sbase(1);

Yload = zeros(nBus,nBus);

Vmag = abs(Vmag(:));

for i = 1:nBus

    if Vmag(i) < 1e-8
        error('Module 14: near-zero voltage at Bus %d.',data.bus(i));
    end

    P = opState.Pload(i);
    Q = opState.Qload(i);

    Psolar = 0;

    if isfield(data,'solarBus') && isfield(opState,'Psolar')

        for s = 1:length(data.solarBus)

            if data.solarBus(s) == data.bus(i) && ...
                    s <= length(opState.Psolar)

                Psolar = Psolar + opState.Psolar(s);
            end
        end
    end

    Pnet = P-Psolar;
    Qnet = Q;

    Yload(i,i) = ...
        conj(Pnet+1j*Qnet)/(Vmag(i)^2);
end

end


%% ========================================================================
% BUILD REDUCED GENERATOR NETWORK
% =========================================================================
function Yred = buildReducedNetworkLocal( ...
    Ybus,Yload,genBus,activeGen,Xd1System,data)

activeGen = activeGen(:);
genBus = genBus(:);
Xd1System = Xd1System(:);

nActive = length(activeGen);
nBus = size(Ybus,1);

if length(Xd1System) == length(genBus)
    XdActive = Xd1System(activeGen);
elseif length(Xd1System) == nActive
    XdActive = Xd1System;
else
    error('Module 14: Xd1 vector length mismatch.');
end

genBusIndex = zeros(nActive,1);

for k = 1:nActive

    b = find(data.bus == genBus(activeGen(k)),1);

    if isempty(b)
        error('Module 14: generator bus mapping failed.');
    end

    genBusIndex(k) = b;
end

Ynetwork = Ybus+Yload;

Yg = diag(1./(1j*XdActive));

Yaug = Ynetwork;

for k = 1:nActive
    b = genBusIndex(k);
    Yaug(b,b) = Yaug(b,b)+Yg(k,k);
end

allBus = (1:nBus).';
nonGen = setdiff(allBus,genBusIndex);

Ygg = Yaug(genBusIndex,genBusIndex);

if isempty(nonGen)

    Yterminal = Ygg;

else

    Ygn = Yaug(genBusIndex,nonGen);
    Yng = Yaug(nonGen,genBusIndex);
    Ynn = Yaug(nonGen,nonGen);

    Yterminal = Ygg-Ygn*(Ynn\Yng);
end

Yred = Yg-Yg*(Yterminal\Yg);

end


%% ========================================================================
% EXPLICIT-HOUR OPERATING CONDITION
% =========================================================================
function op = updateOpCondAtHourLocal(data,currentHour)

loadTime = datetime(string(data.loadTime),'InputFormat','HH:mm');
loadHour = hour(loadTime)+minute(loadTime)/60;

solarTime = datetime(string(data.solarTime),'InputFormat','HH:mm');
solarHour = hour(solarTime)+minute(solarTime)/60;

validLoad = ~isnan(loadHour) & ~isnan(data.LF);
validSolar = ~isnan(solarHour) & ~isnan(data.SF);

loadHour = loadHour(validLoad);
LF = data.LF(validLoad);

solarHour = solarHour(validSolar);
SF = data.SF(validSolar);

[loadHour,iL] = sort(loadHour);
LF = LF(iL);

[solarHour,iS] = sort(solarHour);
SF = SF(iS);

LFcurrent = interp1( ...
    loadHour,LF,currentHour,'linear','extrap');

SFcurrent = interp1( ...
    solarHour,SF,currentHour,'linear','extrap');

op.Pload = data.Pload0*LFcurrent;
op.Qload = data.Qload0*LFcurrent;

op.critical = data.critical;

op.nonShedable_MW = ...
    data.nonShedable_MW*LFcurrent;

op.feederLoad_MW = ...
    data.feederLoad_MW*LFcurrent;

op.feederNonShedable_MW = ...
    data.feederNonShedable_MW*LFcurrent;

op.feederNormalShedable_MW = ...
    data.feederNormalShedable_MW*LFcurrent;

op.Pg = data.Pg0;
op.Qg = data.Qg0;

op.Psolar = data.Psolar0*SFcurrent;
op.solarBus = data.solarBus;

op.LF = LFcurrent;
op.SF = SFcurrent;
op.currentHour = currentHour;

end


%% ========================================================================
% YES / NO
% =========================================================================
function out = yesNo(value)

if value
    out = 'YES';
else
    out = 'NO';
end

end
