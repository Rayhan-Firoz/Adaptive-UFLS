function result = four_newtonRaphson(data, op, Ybus)

% MODULE 4
% Newton-Raphson Power Flow
%
% Bus types:
%   1 = Slack
%   2 = PV
%   3 = PQ
%
% Solar is treated as additional active-power injection.
% Solar does not contribute synchronous-generator inertia.

fprintf('\n');
fprintf('=============================================\n');
fprintf(' MODULE 4: NEWTON-RAPHSON POWER FLOW\n');
fprintf('=============================================\n');

%% =========================================================
% 1. BASIC DATA
% ==========================================================

nBus = length(data.bus);
nGen = length(data.genBus);

G = real(Ybus);
B = imag(Ybus);

busType = data.busType;

% Save original bus types.
% Needed for Q-limit checking.
originalBusType = busType;

%% =========================================================
% 2. GENERATOR POWER AT EACH BUS
% ==========================================================

PgBus = zeros(nBus,1);
QgBus = zeros(nBus,1);

for k = 1:nGen

    b = data.genBus(k);

    PgBus(b) = PgBus(b) + op.Pg(k);
    QgBus(b) = QgBus(b) + op.Qg(k);

end

%% =========================================================
% 3. SOLAR POWER AT EACH BUS
% ==========================================================

PsolarBus = zeros(nBus,1);

for k = 1:length(op.Psolar)

    b = data.solarBus(k);

    PsolarBus(b) = PsolarBus(b) + op.Psolar(k);

end

%% =========================================================
% 4. POWER SPECIFICATION
% ==========================================================

% Active power:
% generator + solar - load
Pspec = PgBus + PsolarBus - op.Pload;

% Reactive power:
% generator - load
Qspec = QgBus - op.Qload;

%% =========================================================
% 5. CHECK SLACK BUS
% ==========================================================

slackBus = find(busType == 1);

if length(slackBus) ~= 1

    error('Module 4: exactly one slack bus is required.');

end

%% =========================================================
% 6. INITIAL VOLTAGE
% ==========================================================

V = ones(nBus,1);
theta = zeros(nBus,1);

% Use operating-condition voltage if available.
if isfield(op,'V')

    V = op.V;

end

% Use operating-condition angle if available.
if isfield(op,'angle')

    theta = op.angle;

elseif isfield(op,'theta')

    theta = op.theta;

end

%% =========================================================
% 7. NEWTON-RAPHSON SETTINGS
% ==========================================================

maxIter = 50;
tolerance = 1e-8;

converged = 0;

%% =========================================================
% 8. Q-LIMIT LOOP
% ==========================================================

maxQLimitLoop = 10;

for qLoop = 1:maxQLimitLoop

    % Current PV buses.
    pvBus = find(busType == 2);

    % Current PQ buses.
    pqBus = find(busType == 3);

    % All non-slack buses have angle variables.
    angleBuses = [pvBus; pqBus];

    nAngle = length(angleBuses);
    nPQ = length(pqBus);

    converged = 0;

    %% =====================================================
    % 9. NEWTON-RAPHSON ITERATION
    % ======================================================

    for iter = 1:maxIter

        % --------------------------------------------------
        % Calculate bus active and reactive power
        % --------------------------------------------------

        Pcalc = zeros(nBus,1);
        Qcalc = zeros(nBus,1);

        for i = 1:nBus

            for j = 1:nBus

                angleDifference = theta(i) - theta(j);

                Pcalc(i) = Pcalc(i) + ...
                    V(i)*V(j)* ...
                    (G(i,j)*cos(angleDifference) + ...
                     B(i,j)*sin(angleDifference));

                Qcalc(i) = Qcalc(i) + ...
                    V(i)*V(j)* ...
                    (G(i,j)*sin(angleDifference) - ...
                     B(i,j)*cos(angleDifference));

            end

        end

        % --------------------------------------------------
        % Calculate mismatch
        % --------------------------------------------------

        dP = Pspec - Pcalc;
        dQ = Qspec - Qcalc;

        mismatch = [dP(angleBuses);
                    dQ(pqBus)];

        maximumMismatch = max(abs(mismatch));

        % --------------------------------------------------
        % Check convergence
        % --------------------------------------------------

        if maximumMismatch < tolerance

            converged = 1;

            break;

        end

        % --------------------------------------------------
        % Create Jacobian
        % --------------------------------------------------

        J1 = zeros(nAngle,nAngle);
        J2 = zeros(nAngle,nPQ);
        J3 = zeros(nPQ,nAngle);
        J4 = zeros(nPQ,nPQ);

        % --------------------------------------------------
        % J1 = dP / dTheta
        % --------------------------------------------------

        for a = 1:nAngle

            i = angleBuses(a);

            for b = 1:nAngle

                j = angleBuses(b);

                if i == j

                    J1(a,b) = ...
                        -Qcalc(i) - B(i,i)*V(i)^2;

                else

                    angleDifference = theta(i) - theta(j);

                    J1(a,b) = ...
                        V(i)*V(j)* ...
                        (G(i,j)*sin(angleDifference) - ...
                         B(i,j)*cos(angleDifference));

                end

            end

        end

        % --------------------------------------------------
        % J2 = dP / dV
        % --------------------------------------------------

        for a = 1:nAngle

            i = angleBuses(a);

            for b = 1:nPQ

                j = pqBus(b);

                if i == j

                    J2(a,b) = ...
                        Pcalc(i)/V(i) + G(i,i)*V(i);

                else

                    angleDifference = theta(i) - theta(j);

                    J2(a,b) = ...
                        V(i)* ...
                        (G(i,j)*cos(angleDifference) + ...
                         B(i,j)*sin(angleDifference));

                end

            end

        end

        % --------------------------------------------------
        % J3 = dQ / dTheta
        % --------------------------------------------------

        for a = 1:nPQ

            i = pqBus(a);

            for b = 1:nAngle

                j = angleBuses(b);

                if i == j

                    J3(a,b) = ...
                        Pcalc(i) - G(i,i)*V(i)^2;

                else

                    angleDifference = theta(i) - theta(j);

                    J3(a,b) = ...
                        -V(i)*V(j)* ...
                        (G(i,j)*cos(angleDifference) + ...
                         B(i,j)*sin(angleDifference));

                end

            end

        end

        % --------------------------------------------------
        % J4 = dQ / dV
        % --------------------------------------------------

        for a = 1:nPQ

            i = pqBus(a);

            for b = 1:nPQ

                j = pqBus(b);

                if i == j

                    J4(a,b) = ...
                        Qcalc(i)/V(i) - B(i,i)*V(i);

                else

                    angleDifference = theta(i) - theta(j);

                    J4(a,b) = ...
                        V(i)* ...
                        (G(i,j)*sin(angleDifference) - ...
                         B(i,j)*cos(angleDifference));

                end

            end

        end

        % --------------------------------------------------
        % Complete Jacobian
        % --------------------------------------------------

        J = [J1 J2;
             J3 J4];

        % --------------------------------------------------
        % Solve Newton-Raphson equations
        % --------------------------------------------------

        dx = J \ mismatch;

        % --------------------------------------------------
        % Update voltage angles
        % --------------------------------------------------

        if nAngle > 0

            theta(angleBuses) = ...
                theta(angleBuses) + dx(1:nAngle);

        end

        % --------------------------------------------------
        % Update PQ voltage magnitudes
        % --------------------------------------------------

        if nPQ > 0

            voltageChange = dx(nAngle+1:end);

            V(pqBus) = ...
                V(pqBus) + voltageChange;

        end

    end

    %% =====================================================
    % 10. CHECK CONVERGENCE
    % ======================================================

    if converged == 0

        error('Module 4: Newton-Raphson did not converge.');

    end

    %% =====================================================
    % 11. CALCULATE FINAL BUS POWERS
    % ======================================================

    Pcalc = zeros(nBus,1);
    Qcalc = zeros(nBus,1);

    for i = 1:nBus

        for j = 1:nBus

            angleDifference = theta(i) - theta(j);

            Pcalc(i) = Pcalc(i) + ...
                V(i)*V(j)* ...
                (G(i,j)*cos(angleDifference) + ...
                 B(i,j)*sin(angleDifference));

            Qcalc(i) = Qcalc(i) + ...
                V(i)*V(j)* ...
                (G(i,j)*sin(angleDifference) - ...
                 B(i,j)*cos(angleDifference));

        end

    end

    %% =====================================================
    % 12. CHECK GENERATOR Q LIMITS
    % ======================================================

    qLimitChanged = 0;

    for k = 1:nGen

        b = data.genBus(k);

        % Only check generators originally operating
        % as PV generators.
        if originalBusType(b) == 2

            Qgenerator = ...
                Qcalc(b) + op.Qload(b);

            % ------------------------------------------------
            % Upper Q limit
            % ------------------------------------------------

            if Qgenerator > data.Qmax(k)

                QgBus(b) = data.Qmax(k);

                Qspec(b) = ...
                    QgBus(b) - op.Qload(b);

                busType(b) = 3;

                qLimitChanged = 1;

                fprintf(['Generator %d reached Qmax. ' ...
                         'Bus %d changed from PV to PQ.\n'], ...
                         k,b);

            % ------------------------------------------------
            % Lower Q limit
            % ------------------------------------------------

            elseif Qgenerator < data.Qmin(k)

                QgBus(b) = data.Qmin(k);

                Qspec(b) = ...
                    QgBus(b) - op.Qload(b);

                busType(b) = 3;

                qLimitChanged = 1;

                fprintf(['Generator %d reached Qmin. ' ...
                         'Bus %d changed from PV to PQ.\n'], ...
                         k,b);

            end

        end

    end

    % If no Q limit was reached, finish.
    if qLimitChanged == 0

        break;

    end

end

%% =========================================================
% 13. FINAL GENERATOR ACTIVE POWER
% ==========================================================

% Start with operating-condition generator powers.
result.Pg = op.Pg;

% The swing generator supplies the remaining active power.
swingGenerator = data.swingGen;
swingBus = data.genBus(swingGenerator);

solarAtSwingBus = PsolarBus(swingBus);

result.Pg(swingGenerator) = ...
    Pcalc(swingBus) + ...
    op.Pload(swingBus) - ...
    solarAtSwingBus;

%% =========================================================
% 14. FINAL GENERATOR REACTIVE POWER
% ==========================================================

result.Qg = op.Qg;

for k = 1:nGen

    b = data.genBus(k);

    % ------------------------------------------------------
    % Swing generator
    % ------------------------------------------------------

    if k == swingGenerator

        result.Qg(k) = ...
            Qcalc(b) + op.Qload(b);

    % ------------------------------------------------------
    % Original PV generator
    % ------------------------------------------------------

    elseif originalBusType(b) == 2

        % Generator became PQ because of Q limit.
        if busType(b) == 3

            result.Qg(k) = QgBus(b);

        else

            result.Qg(k) = ...
                Qcalc(b) + op.Qload(b);

        end

    % ------------------------------------------------------
    % PQ generator
    % ------------------------------------------------------

    else

        result.Qg(k) = QgBus(b);

    end

end

%% =========================================================
% 15. GENERATOR POWER AT EACH BUS
% ==========================================================

result.PgBus = zeros(nBus,1);
result.QgBus = zeros(nBus,1);

for k = 1:nGen

    b = data.genBus(k);

    result.PgBus(b) = ...
        result.PgBus(b) + result.Pg(k);

    result.QgBus(b) = ...
        result.QgBus(b) + result.Qg(k);

end

%% =========================================================
% 16. STORE BUS RESULTS
% ==========================================================

result.V = V;

% Main angle output.
result.angle = theta;

% Keep theta also for compatibility with other modules.
result.theta = theta;

result.Pcalc = Pcalc;
result.Qcalc = Qcalc;

result.PsolarBus = PsolarBus;

result.busType = busType;

%% =========================================================
% 17. FINAL NR MISMATCH
% ==========================================================

% Recalculate final specified powers.
finalPspec = PgBus + PsolarBus - op.Pload;
finalQspec = QgBus - op.Qload;

% Final mismatches.
finaldP = finalPspec - Pcalc;
finaldQ = finalQspec - Qcalc;

% IMPORTANT:
% Slack-bus P is not specified.
% PV-bus Q is not specified.
%
% Therefore only use:
%   P mismatch -> non-slack buses
%   Q mismatch -> PQ buses

finalPMismatch = finaldP(angleBuses);
finalQMismatch = finaldQ(pqBus);

if isempty(finalPMismatch)
    result.maxPError = 0;
else
    result.maxPError = max(abs(finalPMismatch));
end

if isempty(finalQMismatch)
    result.maxQError = 0;
else
    result.maxQError = max(abs(finalQMismatch));
end

result.maxMismatch = max( ...
    [abs(finalPMismatch);
     abs(finalQMismatch)]);

result.converged = ...
    result.maxMismatch < tolerance;

%% =========================================================
% 18. TOTALS
% ==========================================================

% Keep all totals in per-unit.
% No data.baseMVA is used.

result.totalGeneration = sum(result.Pg);

result.totalSolar = sum(op.Psolar);

result.totalLoad = sum(op.Pload);

result.totalQGeneration = sum(result.Qg);

result.totalQLoad = sum(op.Qload);

% Active-power balance in per-unit.
result.powerBalance = ...
    sum(result.Pg) + ...
    sum(op.Psolar) - ...
    sum(op.Pload);

%% =========================================================
% 19. PRINT RESULTS
% ==========================================================

fprintf('\n');

fprintf('Newton-Raphson converged in %d iterations.\n', ...
    iter);

fprintf('Maximum P mismatch = %.10f pu\n', ...
    result.maxPError);

fprintf('Maximum Q mismatch = %.10f pu\n', ...
    result.maxQError);

fprintf('Total synchronous generation = %.8f pu\n', ...
    result.totalGeneration);

fprintf('Total solar generation = %.8f pu\n', ...
    result.totalSolar);

fprintf('Total load = %.8f pu\n', ...
    result.totalLoad);

fprintf('Power balance = %.10f pu\n', ...
    result.powerBalance);

fprintf('=============================================\n');

end
