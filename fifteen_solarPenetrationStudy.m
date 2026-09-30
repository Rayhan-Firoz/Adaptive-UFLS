function study15 = fifteen_solarPenetrationStudy(filename, tripGen, opBase, rngSeed)
%FIFTEEN_SOLARPENETRATIONSTUDY Solar penetration versus required UFLS.
%
% study15 = fifteen_solarPenetrationStudy(filename, tripGen)
% study15 = fifteen_solarPenetrationStudy(filename, tripGen, opBase)
% study15 = fifteen_solarPenetrationStudy(filename, tripGen, [], rngSeed)
%
% opBase is an operating-condition structure returned by two_updateOpCond.
% Pass the same opBase to every comparison that must use exactly the same
% operating condition.  rngSeed is optional and is only used when opBase is
% omitted.  It makes a random two_updateOpCond implementation reproducible.

    if nargin < 2
        error('Use: study15 = fifteen_solarPenetrationStudy(filename, tripGen, opBase, rngSeed);');
    end
    if ~ischar(filename) && ~isstring(filename)
        error('Module 15: filename must be a character vector or string.');
    end
    if nargin < 3
        opBase = [];
    end
    if nargin < 4
        rngSeed = [];
    end

    tripGen = round(tripGen);
    data = one_readInputData(filename);

    Sbase  = data.Sbase(1);
    f0     = data.f0(1);
    fTarget = data.fTarget(1);
    fTrigger = data.UFLStrigger(1);
    UFLSdelay = data.UFLSdelay(1);

    genBus = data.genBus(:);
    Pg0 = data.Pg0(:);
    H0 = data.Hgen(:);
    MVAgen = data.machineRating(:);
    Rgen = data.governor(:);
    Dgen = data.Dgen(:);
    nGen = numel(genBus);

    if tripGen < 1 || tripGen > nGen
        error('Module 15: invalid tripGen = %d.', tripGen);
    end
    if any([numel(Pg0), numel(H0), numel(MVAgen), numel(Rgen), numel(Dgen)] ~= nGen)
        error('Module 15: generator-data vectors must all have length nGen.');
    end

    % Build the operating condition once.  It is never regenerated inside
    % the solar loop.  Restore the caller's random stream after a seeded run.
    if isempty(opBase)
        if ~isempty(rngSeed)
            if ~isnumeric(rngSeed) || ~isscalar(rngSeed) || ...
                    ~isfinite(rngSeed) || rngSeed < 0 || rngSeed ~= floor(rngSeed)
                error('Module 15: rngSeed must be a non-negative integer scalar.');
            end
            oldRng = rng;
            rngCleanup = onCleanup(@() rng(oldRng)); %#ok<NASGU>
            rng(rngSeed, 'twister');
        end
        opBase = two_updateOpCond(data);
    end

    if ~isstruct(opBase) || ~isfield(opBase, 'Pload')
        error('Module 15: opBase must be an operating-condition structure with Pload.');
    end

    % Prefer the generation dispatch in the frozen operating condition.
    % Pg0 remains a backward-compatible fallback for older Module 2 files
    % that only return load data.
    if isfield(opBase, 'Pg') && ~isempty(opBase.Pg)
        PgBase = opBase.Pg(:);
        if numel(PgBase) ~= nGen
            error('Module 15: opBase.Pg must have one value per generator.');
        end
    else
        PgBase = Pg0;
        warning('Module 15: opBase has no Pg field; using static data.Pg0 as the dispatch.');
    end

    if any(~isfinite(PgBase)) || any(PgBase < -1e-9)
        error('Module 15: baseline generator output must be finite and non-negative.');
    end

    baseLoadMW = sum(opBase.Pload(:)) * Sbase;
    if ~isfinite(baseLoadMW) || baseLoadMW <= 0
        error('Module 15: system load must be positive.');
    end

    solarPenetration = (0:5:50).';
    nCase = numel(solarPenetration);
    tripBus = genBus(tripGen);
    activeGen = setdiff((1:nGen).', tripGen);

    % The contingency generator is never displaced by solar.
    candidateGen = setdiff((1:nGen).', tripGen);
    candidateGen = candidateGen(PgBase(candidateGen) > 1e-9);
    [~, order] = sort(PgBase(candidateGen), 'ascend');
    displacementOrder = candidateGen(order);

    solarGenerationMW = zeros(nCase, 1);
    synchronousGenerationMW = zeros(nCase, 1);
    effectiveInertia = zeros(nCase, 1);
    generationLossMW = zeros(nCase, 1);
    initialROCOF = zeros(nCase, 1);
    nadirWithoutUFLS = zeros(nCase, 1);
    nadirWithUFLS = zeros(nCase, 1);
    requiredShedMW = zeros(nCase, 1);
    triggerTime = NaN(nCase, 1);
    sheddingTime = NaN(nCase, 1);
    PgCase = zeros(nCase, nGen);
    HCase = zeros(nCase, nGen);

    % A small numerical tolerance prevents a solver-roundoff difference at
    % exactly fTarget from changing the bisection branch.
    frequencyTolerance = 1e-6;

    fprintf('\n============================================================\n');
    fprintf(' MODULE 15 - SOLAR PENETRATION STUDY\n');
    fprintf('============================================================\n');
    fprintf('Contingency = Gen %d / Bus %d\n', tripGen, tripBus);
    fprintf('Base load   = %.4f MW\n', baseLoadMW);
    fprintf('Target frequency = %.4f Hz\n', fTarget);
    fprintf('UFLS trigger     = %.4f Hz\n', fTrigger);
    fprintf('UFLS delay       = %.4f s\n', UFLSdelay);

    for c = 1:nCase
        penetration = solarPenetration(c);
        requiredSolarMW = penetration / 100 * baseLoadMW;

        % Always start from the same frozen dispatch and inertia data.
        PgCaseCurrent = PgBase;
        HCaseCurrent = H0;
        remainingSolarMW = requiredSolarMW;

        for k = 1:numel(displacementOrder)
            if remainingSolarMW <= 1e-9
                break;
            end
            g = displacementOrder(k);
            generatorMW = PgBase(g) * Sbase;

            if remainingSolarMW >= generatorMW
                PgCaseCurrent(g) = 0;
                HCaseCurrent(g) = 0;
                remainingSolarMW = remainingSolarMW - generatorMW;
            else
                PgCaseCurrent(g) = (generatorMW - remainingSolarMW) / Sbase;
                % A partially loaded synchronous generator remains online,
                % so it retains its inertia.
                HCaseCurrent(g) = H0(g);
                remainingSolarMW = 0;
            end
        end

        % Do not silently claim solar penetration that cannot be supplied by
        % the eligible synchronous generation.
        if remainingSolarMW > 1e-6
            error(['Module 15: %.3f MW of requested solar cannot displace ' ...
                   'the eligible synchronous generation at %.1f %% solar.'], ...
                   remainingSolarMW, penetration);
        end

        actualSolarMW = sum((PgBase - PgCaseCurrent) * Sbase);
        solarGenerationMW(c) = actualSolarMW;
        synchronousGenerationMW(c) = sum(PgCaseCurrent) * Sbase;
        PgCase(c, :) = PgCaseCurrent.';
        HCase(c, :) = HCaseCurrent.';

        % This is a fresh value struct each iteration, so a case cannot
        % mutate the frozen operating condition used by later cases.
        opCase = opBase;
        opCase.Pg = PgCaseCurrent;
        opCase.tripGen = tripGen;

        if isfield(data, 'Psolar0')
            solarProfile = data.Psolar0(:);
            profileTotal = sum(solarProfile);
            if profileTotal > 1e-12
                opCase.Psolar = solarProfile * (actualSolarMW / Sbase) / profileTotal;
            else
                opCase.Psolar = zeros(size(solarProfile));
            end
        else
            opCase.Psolar = [];
        end

        Hsys = sum(HCaseCurrent(activeGen) .* MVAgen(activeGen)) / Sbase;
        if Hsys <= 0
            error('Module 15: effective synchronous inertia is zero.');
        end
        effectiveInertia(c) = Hsys;

        governorGainMWHz = 0;
        generatorDampingMWHz = 0;
        for k = 1:numel(activeGen)
            g = activeGen(k);
            if HCaseCurrent(g) > 1e-9
                if Rgen(g) <= 0
                    error('Module 15: invalid governor droop for Gen %d.', g);
                end
                governorGainMWHz = governorGainMWHz + MVAgen(g) / (Rgen(g) * f0);
                generatorDampingMWHz = generatorDampingMWHz + Dgen(g) * MVAgen(g) / f0;
            end
        end

        loadDampingFraction = data.loadDampingPercent / 100;
        loadDampingMWHz = loadDampingFraction * baseLoadMW / f0;
        DtotalMWHz = loadDampingMWHz + generatorDampingMWHz + governorGainMWHz;

        % The loss must come from the frozen case dispatch, not raw Pg0.
        genLossCaseMW = abs(PgCaseCurrent(tripGen)) * Sbase;
        if genLossCaseMW <= 0
            error('Module 15: Gen %d has zero pre-trip generation.', tripGen);
        end
        generationLossMW(c) = genLossCaseMW;
        initialROCOF(c) = -f0 * genLossCaseMW / (2 * Hsys * Sbase);

        p = struct( ...
            'f0', f0, ...
            'fTrigger', fTrigger, ...
            'fTarget', fTarget, ...
            'UFLSdelay', UFLSdelay, ...
            'Hsys', Hsys, ...
            'Sbase', Sbase, ...
            'PlossMW', genLossCaseMW, ...
            'DtotalMWHz', DtotalMWHz, ...
            'simulationTime', 60);

        % This truly has no UFLS: no trigger event and no artificial solver
        % restart at the trigger frequency.
        noUFLS = runFrequencyTrial(0, p, false);
        nadirWithoutUFLS(c) = noUFLS.nadirHz;

        if noUFLS.nadirHz >= fTarget - frequencyTolerance
            requiredShedMW(c) = 0;
            nadirWithUFLS(c) = noUFLS.nadirHz;
        else
            totalAvailableLoadMW = sum(opCase.Pload(:)) * Sbase;
            maxTrial = runFrequencyTrial(totalAvailableLoadMW, p, true);

            if maxTrial.nadirHz < fTarget - frequencyTolerance
                requiredShedMW(c) = NaN;
                nadirWithUFLS(c) = maxTrial.nadirHz;
                triggerTime(c) = maxTrial.triggerTime;
                sheddingTime(c) = maxTrial.sheddingTime;
                warning(['Module 15: target frequency cannot be maintained ' ...
                         'with available load shedding at %.2f %% solar.'], penetration);
            else
                lowerShed = 0;
                upperShed = totalAvailableLoadMW;
                for iteration = 1:30 %#ok<NASGU>
                    trialShed = (lowerShed + upperShed) / 2;
                    trial = runFrequencyTrial(trialShed, p, true);
                    if trial.nadirHz >= fTarget - frequencyTolerance
                        upperShed = trialShed;
                    else
                        lowerShed = trialShed;
                    end
                    if upperShed - lowerShed < 0.01
                        break;
                    end
                end

                finalTrial = runFrequencyTrial(upperShed, p, true);
                requiredShedMW(c) = upperShed;
                nadirWithUFLS(c) = finalTrial.nadirHz;
                triggerTime(c) = finalTrial.triggerTime;
                sheddingTime(c) = finalTrial.sheddingTime;
            end
        end

        fprintf(['Solar = %5.1f %% | loss = %.4f MW | H = %.4f s-base | ' ...
                 'nadir = %.6f Hz | UFLS = %.4f MW\n'], ...
                 penetration, genLossCaseMW, Hsys, ...
                 nadirWithoutUFLS(c), requiredShedMW(c));
    end

    figure('Name', 'Solar Penetration vs Required Load Shedding', 'NumberTitle', 'off');
    plot(solarPenetration, requiredShedMW, 'o-', 'LineWidth', 1.5, 'MarkerSize', 6);
    grid on;
    xlabel('Solar penetration (%)');
    ylabel('Required load shedding (MW)');
    title(sprintf('Solar Penetration vs Dynamic Required Load Shedding - Gen %d Trip', tripGen));

    figure('Name', 'Solar Penetration vs Frequency Nadir', 'NumberTitle', 'off');
    plot(solarPenetration, nadirWithoutUFLS, 'o-', 'LineWidth', 1.5, 'MarkerSize', 6);
    hold on;
    plot([solarPenetration(1), solarPenetration(end)], [fTarget, fTarget], '--', 'LineWidth', 1.2);
    grid on;
    xlabel('Solar penetration (%)');
    ylabel('Frequency nadir (Hz)');
    title(sprintf('Solar Penetration vs Frequency Nadir - Gen %d Trip', tripGen));
    legend('Without UFLS', 'Target frequency', 'Location', 'best');
    hold off;

    study15 = struct( ...
        'solarPenetration_percent', solarPenetration, ...
        'solarGeneration_MW', solarGenerationMW, ...
        'synchronousGeneration_MW', synchronousGenerationMW, ...
        'effectiveInertia', effectiveInertia, ...
        'generationLoss_MW', generationLossMW, ...
        'initialROCOF_Hz_per_s', initialROCOF, ...
        'nadirWithoutUFLS_Hz', nadirWithoutUFLS, ...
        'nadirWithUFLS_Hz', nadirWithUFLS, ...
        'requiredShed_MW', requiredShedMW, ...
        'triggerTime_s', triggerTime, ...
        'sheddingTime_s', sheddingTime, ...
        'PgCase_MW', PgCase * Sbase, ...
        'HCase_s', HCase, ...
        'baselineGeneration_MW', PgBase * Sbase, ...
        'operatingCondition', opBase, ...
        'tripGen', tripGen, ...
        'tripBus', tripBus, ...
        'baseLoad_MW', baseLoadMW, ...
        'targetFrequency_Hz', fTarget, ...
        'triggerFrequency_Hz', fTrigger, ...
        'UFLSdelay_s', UFLSdelay);
end

function response = runFrequencyTrial(PshedMW, p, enableUFLS)
%RUNFREQUENCYTRIAL Simulate the frequency response with optional UFLS.

    odeOptions = odeset('RelTol', 1e-7, 'AbsTol', 1e-9);
    rhsNoShed = @(t, f) frequencyODE(t, f, p.f0, p.Hsys, p.Sbase, ...
        p.PlossMW, p.DtotalMWHz, 0);

    if ~enableUFLS
        [t, f] = ode45(rhsNoShed, [0, p.simulationTime], p.f0, odeOptions);
        response = makeResponse(t, f, NaN, NaN, p);
        return;
    end

    triggerOptions = odeset(odeOptions, 'Events', ...
        @(t, f) triggerEvent(t, f, p.fTrigger));
    [t1, f1, te, fe] = ode45(rhsNoShed, [0, p.simulationTime], p.f0, triggerOptions);

    if isempty(te)
        response = makeResponse(t1, f1, NaN, NaN, p);
        return;
    end

    tTrigger = te(1);
    fAtTrigger = fe(1);
    tShedding = tTrigger + p.UFLSdelay;

    if p.UFLSdelay > 0 && tShedding < p.simulationTime
        [t2, f2] = ode45(rhsNoShed, [tTrigger, tShedding], fAtTrigger, odeOptions);
    else
        t2 = tTrigger;
        f2 = fAtTrigger;
    end

    if tShedding < p.simulationTime
        rhsShed = @(t, f) frequencyODE(t, f, p.f0, p.Hsys, p.Sbase, ...
            p.PlossMW, p.DtotalMWHz, PshedMW);
        [t3, f3] = ode45(rhsShed, [tShedding, p.simulationTime], f2(end), odeOptions);
    else
        t3 = [];
        f3 = [];
    end

    t = t1;
    f = f1;
    if numel(t2) > 1
        t = [t; t2(2:end)];
        f = [f; f2(2:end)];
    end
    if ~isempty(t3)
        t = [t; t3(2:end)];
        f = [f; f3(2:end)];
    end
    response = makeResponse(t, f, tTrigger, tShedding, p);
end

function response = makeResponse(t, f, triggerTime, sheddingTime, p)
    [response.nadirHz, nadirIndex] = min(f);
    response.time = t;
    response.frequency = f;
    response.nadirTime = t(nadirIndex);
    response.finalHz = f(end);
    response.triggerTime = triggerTime;
    response.sheddingTime = sheddingTime;
    response.initialROCOF = -p.f0 * p.PlossMW / (2 * p.Hsys * p.Sbase);
    response.secure = response.nadirHz >= p.fTarget;
end

function dfdt = frequencyODE(~, f, f0, Hsys, Sbase, PlossMW, DtotalMWHz, PshedMW)
    deltaF = f - f0;
    powerImbalanceMW = -PlossMW + PshedMW - DtotalMWHz * deltaF;
    dfdt = f0 * powerImbalanceMW / (2 * Hsys * Sbase);
end

function [value, isterminal, direction] = triggerEvent(~, f, fTrigger)
    value = f - fTrigger;
    isterminal = 1;
    direction = -1;
end
