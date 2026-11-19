function step3_storage_heat
%% Step 3: Energy storage in Nigerian heat
% Battery-free AED study. Asks how long each stored-energy option stays usable
% when the AED waits for months in Nigerian heat, in two places:
%   cabinet : shaded indoor cabinet with no air conditioning, taken as outdoor air
%   vehicle : closed vehicle parked in the sun (worst case; real vehicles move and park in shade)
% Weather: NASA POWER hourly 2 m air temperature (T2M) and all-sky surface
% shortwave irradiance (ALLSKY_SFC_SW_DWN), 2019 to 2023, local solar time.
% Sites: Ile-Ife, Lagos, Abuja, Maiduguri (Nigeria) and Doha (Qatar, validation).
%
% Vehicle heating rule (lumped thermal model of the cabin):
%   C dT_in/dt = alpha*A*G(t) - UA*(T_in - T_out)
%   steady rise  T_in - T_out = k*G,  k = dT_clear / G_ref
%   time constant tau = 30/ln(4) = 21.6 min  (80 % of the rise in 30 min)
%   dT_clear = 23.5 C (rise reached at steady state on clear days, from the
%   +22 C in 60 min of McLaren, Null and Quinn 2005, Pediatrics 116(1):e109)
%   G_ref = clear-sky irradiance during those measurements: UNVERIFIED, swept
%   1000 / 900 / 800 W/m2 (low / mid / high offset).
% Check: Doha cabin maximum against the 65.7 C measured in parked vehicles in
% Qatar (Alaghawani et al. 2025, BMC Emergency Medicine 25:98).
%
% Parts (datasheet values):
%   Supercapacitor  Eaton HV1860-2R7107-R: 100 F (-10/+30 %), 2.7 V, ESR <= 0.012 ohm,
%                   leakage 260 uA at 20 C after 72 h, life 1000 h at 65 C and 2.7 V
%                   (end of life: 30 % capacitance loss or 200 % ESR), operating to
%                   65 C at 2.7 V (85 C derated to 2.3 V). Life halves per 10 C (Eaton guide).
%   LFP cell        Simpower IFR26650-33A: 3.2 V, 3.3 Ah, self-discharge <= 3.5 %/month
%                   at 25 C and 50 % SOC, storage -20 to 60 C, charge 0 to 45 C.
%   LFP fade        Sandia (Wittman, SAND2022-6841C): about 8 % in about 3 years at 35 C
%                   and 50 % SOC, about 1 % at 15 C. Ea/R = ln(8)/(1/288.15 - 1/308.15).
%
% Units: SI except temperature in C, time in h or days where stated.
% Written as a function: it does not touch the base workspace.
% Needs internet the first time (downloads 25 small CSV files into ./data).

if exist('step3_output.txt','file'), delete('step3_output.txt'); end
diary('step3_output.txt');
dC = [char(176) 'C'];

%% Sites and weather
sites = struct('name', {'Ile-Ife','Lagos','Abuja','Maiduguri','Doha'}, ...
               'lat',  {7.47, 6.45, 9.06, 11.85, 25.29}, ...
               'lon',  {4.56, 3.40, 7.49, 13.16, 51.53});
nS = numel(sites); iNG = 1:4; iDoha = 5;
years = 2019:2023; nY = numel(years);
dataDir = fullfile(pwd, 'data'); if ~isfolder(dataDir), mkdir(dataDir); end

clim = struct('t',{},'T',{},'G',{},'nMiss',{});
for s = 1:nS
    t = datetime.empty(0,1); T = []; G = []; nMiss = 0;
    for y = years
        [ty, Ty, Gy, my] = get_power(sites(s), y, dataDir);
        t = [t; ty]; T = [T; Ty]; G = [G; Gy]; nMiss = nMiss + my; %#ok<AGROW>
    end
    T = fillmissing(T, 'linear', 'EndValues', 'nearest');
    G = max(fillmissing(G, 'linear', 'EndValues', 'nearest'), 0);
    clim(s).t = t; clim(s).T = T; clim(s).G = G; clim(s).nMiss = nMiss;
end
fprintf('Weather: NASA POWER hourly, %d to %d, local solar time.\n', years(1), years(end));
for s = 1:nS
    fprintf('  %-10s %6d hours, %d missing values filled by interpolation\n', ...
            sites(s).name, numel(clim(s).T), clim(s).nMiss);
end
fprintf('Note: T2M is a grid-cell average (about 50 km), so it can sit below a local\n');
fprintf('weather-station maximum. This is a limitation of the data, not of the model.\n\n');

%% Vehicle heating rule
th.tau_min  = 30/log(4);              % [min]
th.dT_clear = 23.5;                   % [C]
th.G_ref    = [1000 900 800];         % [W/m2] low / mid / high offset (UNVERIFIED, swept)
th.k        = th.dT_clear ./ th.G_ref;% [C per W/m2]
caseNames   = {'cabinet','vehicle_low','vehicle_mid','vehicle_high'};
nC = numel(caseNames);
Tcase = cell(nS, nC);
for s = 1:nS
    Tcase{s,1} = clim(s).T;
    for c = 2:nC
        Tcase{s,c} = cabin_temp(clim(s).T, clim(s).G, th.k(c-1), th.tau_min);
    end
end
fprintf('Vehicle rule: tau = %.1f min, rise = k*G with k = %.4f / %.4f / %.4f %s per W/m2 (low/mid/high)\n\n', ...
        th.tau_min, th.k, dC);

%% Check against Qatar measurement
T_meas_car = 65.7; T_meas_bag = 59.1;
fprintf('CHECK, Doha: measured maximum in parked vehicles %.1f %s (medication bags %.1f %s)\n', ...
        T_meas_car, dC, T_meas_bag, dC);
fprintf('  NASA T2M maximum at Doha: %.1f %s\n', max(clim(iDoha).T), dC);
for c = 2:nC
    yrMax = arrayfun(@(y) max(Tcase{iDoha,c}(year(clim(iDoha).t)==y)), years);
    fprintf('  %-13s model maximum %.1f %s (yearly maxima %s), error %+.1f %s\n', ...
            caseNames{c}, max(yrMax), dC, sprintf('%.1f ', yrMax), max(yrMax) - T_meas_car, dC);
end
fprintf('  The measurement year is not matched to these weather years, so compare\n');
fprintf('  the measured value with the spread of yearly maxima, not one exact year.\n\n');

%% Climate summary
TC = table();
for s = 1:nS
    TC = [TC; table(string(sites(s).name), mean(clim(s).T), max(clim(s).T), max(clim(s).G), ...
          max(Tcase{s,2}), max(Tcase{s,3}), max(Tcase{s,4}), ...
          'VariableNames', {'Site','T_out_mean_C','T_out_max_C','G_max_Wm2', ...
          'T_vehicle_max_low_C','T_vehicle_max_mid_C','T_vehicle_max_high_C'})]; %#ok<AGROW>
end
fprintf('Climate summary (%d to %d):\n', years(1), years(end)); disp(TC);
writetable(TC, 'step3_climate.csv');

%% Hours per year above part limits
thr = [35 45 60 65 85];
% 35 C: LFP long-term storage (Power-Sonic) and supercap uncharged 3-year storage (Eaton)
% 45 C: LFP charging limit;  60 C: LFP storage limit (Simpower)
% 65 C: supercap rated at 2.7 V;  85 C: supercap absolute limit (at 2.3 V)
TH = table();
for s = 1:nS
    for c = 1:nC
        h = arrayfun(@(x) sum(Tcase{s,c} > x)/nY, thr);
        TH = [TH; table(string(sites(s).name), string(caseNames{c}), max(Tcase{s,c}), ...
              h(1), h(2), h(3), h(4), h(5), 'VariableNames', ...
              {'Site','Case','T_max_C','h_above35','h_above45','h_above60','h_above65','h_above85'})]; %#ok<AGROW>
    end
end
fprintf('Hours per year above part limits (mean of %d years):\n', nY); disp(TH);
writetable(TH, 'step3_hours_above.csv');

%% Supercapacitor: how many shock charges a given string voltage still gives
% Same averaged flyback model as step 2, now with the datasheet ESR.
p.C_hv = 120e-6; p.V_target = 1700; p.R_leak = 100e6; p.I_out_max = 1.0;
E0 = 0.5*p.C_hv*p.V_target^2;
eta = 0.75;                                   % mid value of the step 2 sweep
sc.n_cells = 6; sc.C_cell = 100; sc.V_cell = 2.7; sc.ESR_cell = 0.012;
sc.I_in_max = 6; sc.P_set = 50;
sc.I_leak20 = 260e-6;                         % [A] at 20 C, 2.7 V, after 72 h (datasheet maximum)
sc.L65 = 1000;                                % [h] life at 65 C and 2.7 V
sc = sc_derive(sc);

s2 = sc; s2.ESR_cell = 0.015; s2 = sc_derive(s2);
n_s2 = sc_count(p, s2, eta, s2.Vmax, Inf);
fprintf('CHECK, step 2 repeat (ESR 0.015 ohm, eta %.2f): %d full charges (step 2 gave 6)\n', eta, n_s2);

capCases = [100 0.012; 90 0.012; 70 0.024; 63 0.024];
capLabel = {'nominal 100 F, new','-10 % tolerance (90 F), new', ...
            'end of life (70 F, 2 x ESR)','-10 % part at end of life (63 F, 2 x ESR)'};
TS = table();
for j = 1:size(capCases,1)
    sj = sc; sj.C_cell = capCases(j,1); sj.ESR_cell = capCases(j,2); sj = sc_derive(sj);
    TS = [TS; table(string(capLabel{j}), capCases(j,1), capCases(j,2), ...
          0.5*sj.C*(sj.Vmax^2 - sj.Vmin^2), sc_count(p, sj, eta, sj.Vmax, Inf), ...
          'VariableNames', {'Cell','C_cell_F','ESR_cell_ohm','E_usable_J','full_charges'})]; %#ok<AGROW>
end
fprintf('Supercapacitor string %d x %g F, %.1f V, full charges of the %.1f J shock capacitor (eta %.2f):\n', ...
        sc.n_cells, sc.C_cell, sc.Vmax, E0, eta); disp(TS);
fprintf('IEC 60601-2-4 201.102.3.1 asks a frequent-use AED for 20 discharges. A full string\n');
fprintf('gives far fewer, so a supercapacitor design must be refilled (crank or solar) during use.\n\n');

V_need1 = sc_vneed(p, sc, eta, 1);
V_need3 = sc_vneed(p, sc, eta, 3);
fprintf('String voltage needed for 1 shock charge: %.2f V; for 3 charges: %.2f V (full %.1f V)\n\n', ...
        V_need1, V_need3, sc.Vmax);

%% Supercapacitor in heat
% (a) Life used up if the string is held full by a solar or mains float charger
%     at 2.7 V per cell: life(T) = 1000 h * 2^((65 - T)/10)        (datasheet + Eaton rule)
%     at 2.3 V per cell: life(T) = 1000 h * 2^((85 - T)/10)
%       The 2.3 V line assumes the rated life also holds at the derated point
%       (85 C, 2.3 V) of the datasheet. UNVERIFIED: the datasheet gives the derating
%       but no life figure at 2.3 V.
% (b) Self-discharge on the shelf after one full charge (crank or solar refilled design)
%     I_leak = I20 * (V/2.7) * 2^((T - 20)/dT_d)
%     The proportional-to-voltage form and the doubling interval dT_d are UNVERIFIED
%     (the datasheet gives one leakage value only); dT_d swept 7 / 10 / 15 C.
dTd = [10 7 15];
horizonSC = 120*24;                           % follow each start for 120 days
TSC = table();
for s = 1:nS
    for c = 1:nC
        Tk = Tcase{s,c};
        dmg = 1 ./ (sc.L65 * 2.^((65 - Tk)/10));          % fraction of life per hour
        life_yr = nY / sum(dmg);
        life23_yr = nY / sum(1 ./ (sc.L65 * 2.^((85 - Tk)/10)));
        dd = zeros(1, numel(dTd)); dd_min = NaN;
        for m = 1:numel(dTd)
            rate = sc.I_leak20/(sc.V_cell*sc.C_cell) .* 2.^((Tk - 20)/dTd(m)) * 3600;  % [1/h]
            days = shelf_days(clim(s).t, rate, log(sc.Vmax/V_need1), horizonSC);
            dd(m) = median(days);
            if m == 1, dd_min = min(days); end
        end
        TSC = [TSC; table(string(sites(s).name), string(caseNames{c}), life_yr, life23_yr, ...
               dd(1), dd_min, dd(2), dd(3), 'VariableNames', ...
               {'Site','Case','life_held_2V7_years','life_held_2V3_years','shelf_days_median','shelf_days_min', ...
                'shelf_days_median_dTd7','shelf_days_median_dTd15'})]; %#ok<AGROW>
    end
end
s23 = sc; s23.V_cell = 2.3; s23 = sc_derive(s23); s23.Vmin = sc.Vmin;
n23 = sc_count(p, s23, eta, s23.Vmax, Inf);
fprintf('Float at 2.3 V per cell (%.1f V string): %d full charges instead of %d at 2.7 V.\n', ...
        s23.Vmax, n23, sc_count(p, sc, eta, sc.Vmax, Inf));
fprintf('Supercapacitor in heat. life_held = years to end of life when held full at 2.7 or 2.3 V per cell;\n');
fprintf('shelf_days = days after one full charge until it can no longer give 1 shock charge\n');
fprintf('(median and minimum over every month start in %d to %d):\n', years(1), years(end));
disp(TSC);
writetable(TSC, 'step3_supercap.csv');

%% LFP battery in heat
% 4S IFR26650-33A: 13.2 V, 3.3 Ah. Starts full.
% Self-discharge r(T) = 3.5 %/month * 2^((T - 25)/10)   (temperature scaling UNVERIFIED)
%   taken as independent of SOC (the datasheet value is at 50 % SOC).
% Standby drain of the AED electronics and self-tests: UNVERIFIED, swept 0 / 0.1 / 0.5 mA.
% Capacity fade: equivalent time at 35 C, t_eq = sum dt * exp(-EaR*(1/T - 1/308.15)),
%   sqrt model  fade = 8 % * sqrt(t_eq / 3 yr)   (sqrt in time UNVERIFIED, common for SEI growth)
%   linear model fade = 8 % * (t_eq / 3 yr)      (reaches 80 % sooner, kept as a bound)
%   Above 35 C this extrapolates the Sandia data; vehicle results are flagged for that reason.
L.Q = 3.3; L.V = 4*3.3; L.sd25 = 0.035; L.month_h = 730.5;
L.EaR = log(8)/(1/288.15 - 1/308.15);
L.fade3 = 0.08; L.t3 = 3;
drains = [0 0.1e-3 0.5e-3];
E_batt = L.Q*L.V*3600;
SOC20 = 20*(E0/eta)/E_batt;
fprintf('LFP 4S: %.0f J stored when full, %.0f shock charges; 20 charges need only %.1f %% SOC.\n', ...
        E_batt, floor(E_batt/(E0/eta)), 100*SOC20);
fprintf('LFP Ea/R from the Sandia points: %.0f K\n', L.EaR);
TL = table();
for s = 1:nS
    for c = 1:nC
        Tk = Tcase{s,c};
        aF = exp(-L.EaR*(1./(Tk + 273.15) - 1/308.15));      % ageing speed relative to 35 C
        teq_per_yr = sum(aF)/8766/nY;                         % equivalent years at 35 C per year
        f1_sqrt = L.fade3*sqrt(teq_per_yr/L.t3);
        f1_lin  = L.fade3*teq_per_yr/L.t3;
        y80_sqrt = L.t3*(0.20/L.fade3)^2/teq_per_yr;
        y80_lin  = L.t3*(0.20/L.fade3)/teq_per_yr;
        sdr = L.sd25/L.month_h .* 2.^((Tk - 25)/10);         % SOC lost per hour
        soc6 = zeros(1,numel(drains)); soc12 = soc6; mo_empty = soc6;
        for m = 1:numel(drains)
            dr = sdr + drains(m)/L.Q;                         % SOC lost per hour incl. drain
            soc6(m)  = max(0, 1 - max(window_sum(clim(s).t, dr, round(6*L.month_h))));
            soc12(m) = max(0, 1 - max(window_sum(clim(s).t, dr, 8766)));
            % months until fewer than 20 shock charges are left (worst month start)
            mo_empty(m) = min(shelf_days(clim(s).t, dr, 1 - SOC20, 24*730)) / (730.5/24);
        end
        TL = [TL; table(string(sites(s).name), string(caseNames{c}), teq_per_yr, ...
              100*f1_sqrt, 100*f1_lin, y80_sqrt, y80_lin, ...
              100*soc6(1), 100*soc12(1), mo_empty(1), mo_empty(2), mo_empty(3), 'VariableNames', ...
              {'Site','Case','teq35_yr_per_yr','fade_1yr_sqrt_pct','fade_1yr_lin_pct', ...
               'years_to_80pct_sqrt','years_to_80pct_lin', ...
               'SOC_6mo_worst_pct','SOC_12mo_worst_pct','months_to_empty_0mA','months_to_empty_0p1mA','months_to_empty_0p5mA'})]; %#ok<AGROW>
    end
end
fprintf('LFP in heat. SOC values are the worst over every month start (0 = empty).\n');
fprintf('months_to_empty = worst-case months from full until fewer than 20 shock charges are left\n');
fprintf('(standby drain 0 / 0.1 / 0.5 mA; 24 means 24 or more).\n');
disp(TL);
writetable(TL, 'step3_lfp.csv');

%% Crank design: readiness including electronics start-up
% Heat does not drain a crank design, because it stores nothing between uses.
% Start-up time of the electronics from the crank: UNVERIFIED, swept 1 / 2 / 5 s.
t_analysis = 8; t_limit = 30; t_start = [1 2 5]; P_crank = [20 24 54];
f2 = fullfile('..','charger','step2_A_crank.csv');
if isfile(f2)
    A = readtable(f2);
    t_chg = interp1(A.P_crank_W, A.t_eta075_s, P_crank);
    src = 'step 2 results (step2_A_crank.csv)';
else
    t_chg = E0 ./ (eta*P_crank);
    src = 'closed form E0/(eta*P) because step2_A_crank.csv was not found';
end
TR = table();
for a = 1:numel(P_crank)
    r = t_start + t_analysis + t_chg(a);
    TR = [TR; table(P_crank(a), t_chg(a), r(1), r(2), r(3), all(r <= t_limit), ...
          'VariableNames', {'P_crank_W','t_charge_s','ready_start1s','ready_start2s', ...
          'ready_start5s','meets_30s_all'})]; %#ok<AGROW>
end
fprintf('Crank readiness = start-up + %.0f s analysis + charge time (charge time from %s):\n', t_analysis, src);
disp(TR);
writetable(TR, 'step3_crank_readiness.csv');

%% Figure 1: hottest hour in each month
cols = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19];
f1 = figure('Color','w','Position',[40 40 1250 700]);
tl = tiledlayout(f1, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
mlab = {'J','F','M','A','M','J','J','A','S','O','N','D'};
for s = 1:nS
    ax = nexttile(tl); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
    mo = month(clim(s).t);
    Tm = zeros(12, nC);
    for c = 1:nC, Tm(:,c) = accumarray(mo, Tcase{s,c}, [12 1], @max); end
    fill(ax, [1:12 12:-1:1], [Tm(:,2)' fliplr(Tm(:,4)')], cols(2,:), 'FaceAlpha', 0.20, ...
         'EdgeColor', 'none', 'DisplayName', 'Parked vehicle, low to high offset');
    plot(ax, 1:12, Tm(:,3), '-o', 'Color', cols(2,:), 'LineWidth', 1.4, 'MarkerSize', 4, ...
         'DisplayName', 'Parked vehicle, mid offset');
    plot(ax, 1:12, Tm(:,1), '-s', 'Color', cols(1,:), 'LineWidth', 1.4, 'MarkerSize', 4, ...
         'DisplayName', 'Shaded cabinet (outdoor air)');
    plot(ax, [1 12], [60 60], '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.0, ...
         'DisplayName', ['LFP storage limit, 60 ' dC]);
    plot(ax, [1 12], [65 65], ':', 'Color', 'k', 'LineWidth', 1.3, ...
         'DisplayName', ['Supercapacitor rating at 2.7 V, 65 ' dC]);
    if s == iDoha
        plot(ax, [1 12], [T_meas_car T_meas_car], '-.', 'Color', cols(3,:), 'LineWidth', 1.4, ...
             'DisplayName', ['Measured vehicle maximum, Qatar, 65.7 ' dC]);
    end
    xlim(ax, [1 12]); ylim(ax, [20 90]); xticks(ax, 1:12); xticklabels(ax, mlab);
    title(ax, sites(s).name);
    ylabel(ax, ['Hottest hour in month (' dC ')']);
    set(ax, 'FontName', 'Times New Roman', 'FontSize', 11);
end
lgd = legend(ax, 'Location', 'layout'); lgd.Layout.Tile = 6;
set(lgd, 'FontName', 'Times New Roman', 'FontSize', 11, 'Box', 'off');
title(tl, sprintf('Storage temperature of an AED, NASA POWER %d to %d', years(1), years(end)), ...
      'FontName', 'Times New Roman', 'FontSize', 13);
exportgraphics(f1, 'fig_step3_temperature.png', 'Resolution', 300);

%% Figure 2: storage results for the Nigerian sites
f2h = figure('Color','w','Position',[60 60 1150 820]);
tl2 = tiledlayout(f2h, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
pick = @(Tab, var, cs) arrayfun(@(s) Tab.(var)(Tab.Site==sites(s).name & Tab.Case==cs), iNG);
panels = {TSC, 'life_held_2V7_years',   '(a) Supercapacitor held full at 2.7 V',     'Years to end of life';
          TSC, 'shelf_days_median',     '(b) Supercapacitor left after one charge',  'Days until no shock is left';
          TL,  'years_to_80pct_lin',    '(c) LFP battery capacity fade',             'Years to 80 % capacity';
          TL,  'months_to_empty_0p1mA', '(d) LFP battery with 0.1 mA standby drain', 'Months until under 20 shocks'};
for k = 1:size(panels,1)
    ax = nexttile(tl2); hold(ax,'on'); box(ax,'on'); grid(ax,'on');
    Tab = panels{k,1}; v = panels{k,2};
    yc = pick(Tab, v, "cabinet"); ym = pick(Tab, v, "vehicle_mid");
    yl = pick(Tab, v, "vehicle_low"); yh = pick(Tab, v, "vehicle_high");
    b = bar(ax, 1:numel(iNG), [yc(:) ym(:)], 'grouped');
    b(1).FaceColor = cols(1,:); b(2).FaceColor = cols(2,:);
    b(1).DisplayName = 'Shaded cabinet';
    b(2).DisplayName = 'Parked vehicle, mid offset (error bar: low to high offset)';
    xe = b(2).XEndPoints;
    errorbar(ax, xe, ym, ym - min(yl,yh), max(yl,yh) - ym, 'k.', 'LineWidth', 1.0, ...
             'HandleVisibility', 'off');
    xticks(ax, 1:numel(iNG)); xticklabels(ax, {sites(iNG).name}); xlim(ax, [0.4 numel(iNG)+0.6]);
    ylim(ax, [0 1.15*max([yc(:); yl(:); yh(:)])]);
    title(ax, panels{k,3}, 'FontWeight', 'normal');
    ylabel(ax, panels{k,4});
    set(ax, 'FontName', 'Times New Roman', 'FontSize', 12);
end
lgd2 = legend(ax, 'Orientation', 'horizontal', 'Box', 'off');
lgd2.Layout.Tile = 'south';
set(lgd2, 'FontName', 'Times New Roman', 'FontSize', 12);
exportgraphics(f2h, 'fig_step3_storage.png', 'Resolution', 300);

diary off;
fprintf(['Saved step3_output.txt, step3_climate.csv, step3_hours_above.csv, step3_supercap.csv,\n' ...
         'step3_lfp.csv, step3_crank_readiness.csv, fig_step3_temperature.png, fig_step3_storage.png\n']);
end

%% ------------------------------------------------------------------------
function [t, T, G, nMiss] = get_power(site, yr, dataDir)
% Hourly T2M [C] and ALLSKY_SFC_SW_DWN [Wh/m2 per hour = mean W/m2] from NASA POWER.
% Downloads once, then reads the saved CSV.
    fname = fullfile(dataDir, sprintf('power_%s_%d.csv', strrep(site.name,'-',''), yr));
    if ~isfile(fname)
        url = sprintf(['https://power.larc.nasa.gov/api/temporal/hourly/point?' ...
              'parameters=T2M,ALLSKY_SFC_SW_DWN&community=RE&longitude=%.2f&latitude=%.2f' ...
              '&start=%d0101&end=%d1231&format=CSV&time-standard=LST'], site.lon, site.lat, yr, yr);
        fprintf('Downloading %s %d from NASA POWER ...\n', site.name, yr);
        try
            txt = webread(url, weboptions('Timeout', 180, 'ContentType', 'text'));
        catch err
            error('Download failed for %s %d: %s\nURL: %s', site.name, yr, err.message, url);
        end
        fid = fopen(fname, 'w');
        if fid < 0, error('Cannot write %s. Check the folder is writable.', fname); end
        fwrite(fid, txt, 'char'); fclose(fid);
    end
    lines = splitlines(string(fileread(fname)));
    iH = find(startsWith(strtrim(lines), "YEAR"), 1);
    if isempty(iH)
        delete(fname);
        error('File for %s %d had no data header, deleted it. Run again to re-download.', site.name, yr);
    end
    hdr = strtrim(split(lines(iH), ","));
    M = readmatrix(fname, 'FileType', 'text', 'Delimiter', ',', 'NumHeaderLines', iH);
    M = M(all(~isnan(M(:,1:4)),2), :);
    col = @(nm) M(:, find(hdr == nm, 1));
    t = datetime(col("YEAR"), col("MO"), col("DY"), col("HR"), 0, 0);
    T = col("T2M"); G = col("ALLSKY_SFC_SW_DWN");
    T(T <= -998) = NaN; G(G <= -998) = NaN;
    nMiss = sum(isnan(T)) + sum(isnan(G));
    if numel(t) < 8760
        error('Only %d hours for %s %d. Delete %s and run again.', numel(t), site.name, yr, fname);
    end
end

function Tin = cabin_temp(Tout, G, k, tau_min)
% Exact step of C dTin/dt = UA*(Tout + k*G - Tin) with inputs held over each hour.
    a = exp(-60/tau_min);
    Teq = Tout + k*G;
    Tin = zeros(size(Tout)); Tin(1) = Teq(1);
    for n = 2:numel(Tout)
        Tin(n) = Teq(n) + (Tin(n-1) - Teq(n))*a;
    end
end

function sc = sc_derive(sc)
    sc.C = sc.C_cell/sc.n_cells; sc.ESR = sc.ESR_cell*sc.n_cells;
    sc.Vmax = sc.V_cell*sc.n_cells; sc.Vmin = sc.Vmax/2;
end

function n = sc_count(p, s, eta, v0, nmax)
% Full charges of the HV capacitor from a supercapacitor string starting at v0
% (same equations as supercap_shocks in step 2).
    v_sc = v0; n = 0;
    while n < nmax && v_sc > s.Vmin
        opts = odeset('Events', @(t,x) ev(x), 'RelTol', 1e-7, 'AbsTol', 1e-7);
        [~, ~, ~, xe, ie] = ode45(@(t,x) rhs(x), [0 600], [0; v_sc], opts);
        if isempty(ie) || ie(end) ~= 1, break; end
        n = n + 1; v_sc = xe(end,2);
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

function V = sc_vneed(p, s, eta, k)
% Lowest string voltage that still gives k full charges (bisection).
    lo = s.Vmin; hi = s.Vmax;
    if sc_count(p, s, eta, hi, k) < k, V = NaN; return; end
    for it = 1:30
        mid = 0.5*(lo + hi);
        if sc_count(p, s, eta, mid, k) >= k, hi = mid; else, lo = mid; end
    end
    V = hi;
end

function I = solve_current(V, R, P)
    disc = V^2 - 4*R*P;
    if disc < 0, I = V/(2*R); else, I = (V - sqrt(disc))/(2*R); end
end

function days = shelf_days(t, rate, lnDrop, horizon_h)
% Voltage decays as V = V0*exp(-cumulative rate). For each month start, days until
% the cumulative rate reaches lnDrop = ln(V0/V_need).
    starts = find(day(t) == 1 & hour(t) == 0);
    starts = starts(starts + horizon_h - 1 <= numel(t));
    cr = [0; cumsum(rate(:))];
    days = nan(numel(starts), 1);
    for j = 1:numel(starts)
        i0 = starts(j);
        seg = cr(i0+1:i0+horizon_h) - cr(i0);
        m = find(seg >= lnDrop, 1);
        if isempty(m), days(j) = horizon_h/24; else, days(j) = m/24; end   % 120 means 120 or more
    end
end

function w = window_sum(t, x, len)
% Sum of x over len hours from every month start that has len hours of data after it.
    starts = find(day(t) == 1 & hour(t) == 0);
    starts = starts(starts + len - 1 <= numel(t));
    cx = [0; cumsum(x(:))];
    w = cx(starts + len) - cx(starts);
end
