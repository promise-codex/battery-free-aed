function step2_charger_average
%% Step 2: Charging the shock capacitor (averaged flyback model)
% Battery-free AED study. Charges the 120 uF high-voltage capacitor to 1700 V
% (173.4 J, the step 1 design) from three energy sources:
%   A. hand crank feeding the flyback directly (Dhurjaty and Atre 2016 style)
%   B. supercapacitor string feeding the flyback (crank or solar refills it)
%   C. 4-cell LFP lithium-ion battery feeding the flyback
% The flyback is modelled by its average power flow (no switching detail):
%   output current into the HV capacitor  i_hv = min(eta*P_in / v_hv, I_out_max)
% This is valid because the switching period (about 20 us at 50 kHz) is far
% shorter than the charge time (seconds). The switch-level model comes later.
% Units: SI (F, V, ohm, s, J, A, W).
% Written as a function: it does not touch the base workspace.

if exist('step2_output.txt','file'), delete('step2_output.txt'); end
diary('step2_output.txt');

%% Shared parameters
p.C_hv      = 120e-6;   % HV capacitor [F]               (Dhurjaty and Atre 2016)
p.V_target  = 1700;     % charge voltage [V]             (Dhurjaty and Atre 2016)
p.R_leak    = 100e6;    % HV capacitor leakage [ohm]     (UNVERIFIED, effect negligible)
p.I_out_max = 1.0;      % flyback output current limit [A] (UNVERIFIED, only matters below ~20 V)
E_target    = 0.5*p.C_hv*p.V_target^2;
etas        = [0.65 0.75 0.85];    % flyback efficiency range (UNVERIFIED, swept)
t_analysis  = 8;        % rhythm analysis time [s]: two 4 s windows (study assumption)
t_limit     = 30;       % IEC 60601-2-4 201.15.4.3.103 b): AED ready within 30 s
fprintf('Target stored energy: %.1f J at %.0f V\n\n', E_target, p.V_target);

%% A. Hand crank direct
% Electrical power from the crank generator, swept from a tired rescuer (20 W)
% to the mean sustained one-hand cranking power (54 W, Jansen and Slob 2003).
P_crank = [20 24 30 40 54];
tA = zeros(numel(P_crank), numel(etas));
for a = 1:numel(P_crank)
    for b = 1:numel(etas)
        tA(a,b) = charge_time_const_power(p, P_crank(a), etas(b));
    end
end
TA = array2table([P_crank(:) tA], 'VariableNames', ...
     {'P_crank_W','t_eta065_s','t_eta075_s','t_eta085_s'});
fprintf('A. Hand crank direct: charge time [s]\n'); disp(TA);
fprintf('Check vs Dhurjaty and Atre (24 W, reported 8 to 12 s): %.1f to %.1f s over eta 0.65 to 0.85\n', ...
        min(tA(P_crank==24,:)), max(tA(P_crank==24,:)));
fprintf('Note: at 24 W any efficiency from %.2f to %.2f gives 8 to 12 s, so this check confirms\n', ...
        E_target/(24*12), min(1, E_target/(24*8)));
fprintf('consistency of the energy budget, not the efficiency value itself.\n\n');
writetable(TA, 'step2_A_crank.csv');

%% B. Supercapacitor string
s.n_cells   = 6;        % cells in series
s.C_cell    = 100;      % F per cell                     (study choice, swept later)
s.V_cell    = 2.7;      % V per cell, rated
s.ESR_cell  = 0.015;    % ohm per cell                   (UNVERIFIED, set from datasheet later)
s.I_in_max  = 6;        % flyback input current limit [A] (UNVERIFIED)
s.P_set     = 50;       % flyback input power setpoint [W] (study choice)
s.C   = s.C_cell/s.n_cells;  s.ESR = s.ESR_cell*s.n_cells;
s.Vmax = s.V_cell*s.n_cells; s.Vmin = s.Vmax/2;
E_use = 0.5*s.C*(s.Vmax^2 - s.Vmin^2);
fprintf('B. Supercapacitor: %d x %g F, %.1f V: C = %.2f F, usable energy %.0f J (Vmin = %.1f V)\n', ...
        s.n_cells, s.C_cell, s.Vmax, s.C, E_use, s.Vmin);
TB = table();
for b = 1:numel(etas)
    [n_shocks, t_first, t_last] = supercap_shocks(p, s, etas(b));
    TB = [TB; table(etas(b), n_shocks, t_first, t_last, ...
          'VariableNames', {'eta','full_charges','t_first_s','t_last_s'})]; %#ok<AGROW>
end
disp(TB);
writetable(TB, 'step2_B_supercap.csv');

%% C. LFP battery, 4 cells in series
L.V_ocv   = 4*3.3;      % open-circuit voltage [V], LFP nominal 3.2 to 3.3 V per cell
L.R0      = 4*0.02;     % internal resistance [ohm]      (UNVERIFIED, set from datasheet later)
L.I_in_max= 6;          % same flyback input limit [A]
L.P_set   = 50;         % same power setpoint [W]
TC = table();
for b = 1:numel(etas)
    I = solve_current(L.V_ocv, L.R0, L.P_set);
    P_in = min(L.P_set, (L.V_ocv - min(I,L.I_in_max)*L.R0)*min(I,L.I_in_max));
    t = charge_time_const_power(p, P_in, etas(b));
    TC = [TC; table(etas(b), P_in, t, 'VariableNames', {'eta','P_in_W','t_charge_s'})]; %#ok<AGROW>
end
fprintf('C. LFP battery 4S (%.1f V): charge time\n', L.V_ocv); disp(TC);
writetable(TC, 'step2_C_battery.csv');

%% Readiness against the IEC 30 s limit (analysis time + charge time)
fprintf('Readiness = %.0f s analysis + charge time, limit %.0f s (eta = 0.75):\n', t_analysis, t_limit);
fprintf('  A. crank 20 W: %.1f s   crank 24 W: %.1f s   crank 54 W: %.1f s\n', ...
    t_analysis + tA(1,2), t_analysis + tA(2,2), t_analysis + tA(end,2));
fprintf('  B. supercap  : %.1f s (first charge)\n', t_analysis + TB.t_first_s(2));
fprintf('  C. battery   : %.1f s\n', t_analysis + TC.t_charge_s(2));
fprintf('  For A, the electronics must also start up from the crank before analysis. Not yet included.\n\n');

%% Energy balance check for one run (crank 24 W, eta 0.75)
[t_chk, E_in, E_cap, E_loss_fb, E_leak] = charge_time_const_power(p, 24, 0.75);
bal = (E_in - (E_cap + E_loss_fb + E_leak))/E_in*100;
fprintf('Energy balance (24 W, eta 0.75): in %.2f J = cap %.2f + flyback loss %.2f + leakage %.4f J; error %.3f %% (must be < 1 %%)\n\n', ...
        E_in, E_cap, E_loss_fb, E_leak, bal);

%% Figure: charge time versus crank power
figure('Color','w','Position',[100 100 760 420]); hold on; box on;
mk = {'o-','s-','^-'};
for b = 1:numel(etas)
    plot(P_crank, tA(:,b), mk{b}, 'LineWidth', 1.5, 'DisplayName', sprintf('\\eta = %.2f', etas(b)));
end
yline(t_limit - t_analysis, 'r--', 'Time left for charging within the 30 s limit', 'LineWidth', 1.2, ...
      'LabelHorizontalAlignment','left', 'HandleVisibility','off');
plot([24 24], [8 12], 'k-', 'LineWidth', 4, 'DisplayName', 'Dhurjaty and Atre 2016 (8 to 12 s)');
xlabel('Electrical power from hand crank (W)'); ylabel('Time to charge 120 \muF to 1700 V (s)');
title('Hand-crank charging of the shock capacitor');
legend('Location','northeast'); set(gca,'FontName','Times New Roman','FontSize',12);
exportgraphics(gcf, 'fig_step2_crank_charge_time.png', 'Resolution', 300);

diary off;
fprintf('Saved step2_output.txt, step2_A_crank.csv, step2_B_supercap.csv, step2_C_battery.csv, fig_step2_crank_charge_time.png\n');
end

%% ------------------------------------------------------------------------
function [t_end, E_in, E_cap, E_loss_fb, E_leak] = charge_time_const_power(p, P_in, eta)
% HV capacitor charged at constant input power P_in through a flyback of efficiency eta.
% States: x = [v_hv; E_in; E_leak]
    f = @(t,x) [ (i_out(x(1)) - x(1)/p.R_leak)/p.C_hv ;
                 P_in_used(x(1)) ;
                 x(1)^2/p.R_leak ];
    function i = i_out(v)
        i = min(eta*P_in/max(v,1e-3), p.I_out_max);
    end
    function P = P_in_used(v)
        P = i_out(v)*v/eta;             % input power actually drawn (less than P_in while current-limited)
    end
    function [val, term, dir] = evFull(~, x)
        val = x(1) - p.V_target; term = 1; dir = 1;   % stop when the HV capacitor is full
    end
    opts = odeset('Events', @evFull, 'RelTol', 1e-8, 'AbsTol', 1e-8);
    [~, ~, te, xe] = ode45(f, [0 600], [0;0;0], opts);
    t_end = te(end); E_in = xe(end,2); E_leak = xe(end,3);
    E_cap = 0.5*p.C_hv*xe(end,1)^2;
    E_loss_fb = (1-eta)*E_in;
end

function I = solve_current(V, R, P)
% Current drawn from a source V with series resistance R to deliver power P at its terminals.
    disc = V^2 - 4*R*P;
    if disc < 0, I = V/(2*R); else, I = (V - sqrt(disc))/(2*R); end
end

function [n, t_first, t_last] = supercap_shocks(p, s, eta)
% Repeated full charges of the HV capacitor from one full supercapacitor string.
    v_sc = s.Vmax; n = 0; t_first = NaN; t_last = NaN;
    while true
        f = @(t,x) rhs(x);
        opts = odeset('Events', @(t,x) ev(x), 'RelTol', 1e-7, 'AbsTol', 1e-7);
        [~, ~, te, xe, ie] = ode45(f, [0 600], [0; v_sc], opts);
        if isempty(ie) || ie(end) ~= 1, break; end      % stopped by Vmin, not by full charge
        n = n + 1; v_sc = xe(end,2);
        if n == 1, t_first = te(end); end
        t_last = te(end);
    end
    function dx = rhs(x)
        v_hv = x(1); vs = x(2);
        P_avail = min(s.P_set, max(vs - s.I_in_max*s.ESR, 0)*s.I_in_max);
        I = solve_current(vs, s.ESR, P_avail);
        i_hv = min(eta*P_avail/max(v_hv,1e-3), p.I_out_max);
        P_used = i_hv*v_hv/eta;
        I_used = I*P_used/max(P_avail,1e-9);
        dx = [ (i_hv - v_hv/p.R_leak)/p.C_hv ; -I_used/s.C ];
    end
    function [val, term, dir] = ev(x)
        val = [x(1) - p.V_target; x(2) - s.Vmin]; term = [1;1]; dir = [1;-1];
    end
end
