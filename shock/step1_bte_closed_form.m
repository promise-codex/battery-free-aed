%% Step 1: Biphasic truncated exponential (BTE) shock, closed-form model
% Battery-free AED study. Computes stored, residual and delivered energy,
% peak current and pulse duration at the seven IEC 60601-2-4 test loads
% (clause 201.12.1: 25, 50, 75, 100, 125, 150, 175 ohm).
% Check case: Dhurjaty and Atre 2016 (120 uF charged to 1700 V, truncated at 150 V).
% Units: SI throughout (F, V, ohm, s, J, A).

% Note: no clear/clc here, so other work in the MATLAB workspace and Command Window is left alone.
% All printed output is also saved to step1_output.txt, and the table to step1_results.csv.
if exist('step1_output.txt','file'), delete('step1_output.txt'); end
diary('step1_output.txt');

%% Parameters
C_hv   = 120e-6;            % high-voltage capacitor [F]   (Dhurjaty and Atre 2016)
V0     = 1700;              % charge voltage [V]           (Dhurjaty and Atre 2016)
V_trunc= 150;               % truncation voltage [V]       (Dhurjaty and Atre 2016)
r_int  = 5;                 % internal series resistance [ohm] (UNVERIFIED, swept below)
t_cap  = 20e-3;             % total pulse duration cap [s] (study choice, 18 ms sensitivity)
split  = 0.60;              % phase 1 share of total duration (fixed convention)
R_iec  = [25 50 75 100 125 150 175];   % IEC test loads [ohm]

%% Closed-form calculation for one configuration
E0 = 0.5*C_hv*V0^2;         % stored energy [J]
fprintf('Stored energy E0 = %.1f J\n\n', E0);

res = bte_table(C_hv, V0, V_trunc, r_int, t_cap, split, R_iec);
disp(res);
writetable(res, 'step1_results.csv');

%% Sensitivity: internal resistance 2 to 10 ohm, and 18 ms cap
fprintf('\nSensitivity of delivered energy [J] to internal resistance and cap:\n');
for r = [2 5 10]
    for cap = [18e-3 20e-3]
        T = bte_table(C_hv, V0, V_trunc, r, cap, split, R_iec);
        fprintf('r_int = %2d ohm, cap = %2.0f ms: %s\n', r, cap*1e3, mat2str(round(T.E_del_J',1)));
    end
end

%% Check against hand calculation in the study breakdown (r_int = 5 ohm, 20 ms cap)
expected = [143.4 156.4 NaN NaN NaN NaN 142.1];   % 25, 50 and 175 ohm values from the breakdown
idx = ~isnan(expected);
err = abs(res.E_del_J(idx)' - expected(idx));
fprintf('\nMax difference from hand calculation: %.2f J (should be < 0.1 J)\n', max(err));

%% IEC energy accuracy band, using the 50 ohm value as the rated energy (illustration only)
E_rated = res.E_del_J(R_iec==50);
tol = max(3, 0.15*E_rated);
inBand = abs(res.E_del_J - E_rated) <= tol;
fprintf('If rated energy = %.1f J at every load, band = +/-%.1f J. Loads inside band: %s\n', ...
        E_rated, tol, mat2str(R_iec(inBand')));

%% Figure: waveforms at 25, 75 and 175 ohm
figure('Color','w','Position',[100 100 760 420]); hold on; box on;
for R = [25 75 175]
    [t, i] = bte_current(C_hv, V0, V_trunc, r_int, t_cap, split, R);
    plot(t*1e3, i, 'LineWidth', 1.6, 'DisplayName', sprintf('%d \\Omega', R));
end
yline(0,'k:','HandleVisibility','off');
xlabel('Time (ms)'); ylabel('Patient current (A)');
title('Biphasic truncated exponential shock, 120 \muF charged to 1700 V');
legend('Location','northeast'); set(gca,'FontName','Times New Roman','FontSize',12);
exportgraphics(gcf, 'fig_step1_bte_waveforms.png', 'Resolution', 300);
diary off;
fprintf('Saved step1_output.txt, step1_results.csv and fig_step1_bte_waveforms.png\n');

%% ------------------------------------------------------------------------
function T = bte_table(C, V0, Vtr, r, tcap, split, R)
    n = numel(R);
    [tau_ms, t_ms, t1_ms, t2_ms, Vend, Eres, Edel, Ipk, tilt] = deal(zeros(n,1));
    E0 = 0.5*C*V0^2;
    for k = 1:n
        tau    = (R(k)+r)*C;                       % time constant [s]
        t_full = tau*log(V0/Vtr);                  % time to fall to truncation voltage [s]
        t_tot  = min(t_full, tcap);                % duration with cap [s]
        Ve     = V0*exp(-t_tot/tau);               % end voltage [V]
        Er     = 0.5*C*Ve^2;                       % energy left in capacitor [J]
        Ed     = (E0 - Er)*R(k)/(R(k)+r);          % energy delivered to patient [J]
        tau_ms(k)=tau*1e3; t_ms(k)=t_tot*1e3; t1_ms(k)=split*t_tot*1e3; t2_ms(k)=(1-split)*t_tot*1e3;
        Vend(k)=Ve; Eres(k)=Er; Edel(k)=Ed; Ipk(k)=V0/(R(k)+r); tilt(k)=100*(V0-Ve)/V0;
    end
    T = table(R(:), tau_ms, t_ms, t1_ms, t2_ms, Vend, tilt, Eres, Edel, Ipk, ...
        'VariableNames', {'R_ohm','tau_ms','dur_ms','phase1_ms','phase2_ms','V_end_V','tilt_pct','E_res_J','E_del_J','I_peak_A'});
end

function [t, i] = bte_current(C, V0, Vtr, r, tcap, split, R)
    tau   = (R+r)*C;
    t_tot = min(tau*log(V0/Vtr), tcap);
    t     = linspace(0, t_tot, 2000);
    v     = V0*exp(-t/tau);
    sgn   = ones(size(t)); sgn(t > split*t_tot) = -1;   % H-bridge reverses polarity
    i     = sgn.*v/(R+r);
    t = [t t_tot t_tot+1e-3]; i = [i 0 0];               % show the end of the pulse
end
