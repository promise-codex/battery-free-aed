function step4_solar_sizing
%% Step 4: Sizing a small solar panel to keep the AED ready
% Battery-free AED study. Step 3 showed that a supercapacitor keeps a shock for
% only days and an LFP battery for months. Here a small solar panel tops them up.
% For each panel size the hourly NASA POWER weather (2019 to 2023) is run through:
%   1. standby: is there enough stored energy, every hour of five years?
%        supercapacitor: at least 3 shock charges (IEC 60601-2-4 201.15.4.3.101
%                        asks for 3 discharges after the replacement indication)
%        LFP battery    : at least 20 shock charges (IEC 60601-2-4 201.102.3.1)
%   2. recovery: after a rescue empties the supercapacitor, how long until the sun
%      alone gives 3 charges again? (The crank covers the gap.)
% Cases (as step 3): cabinet = storage at outdoor air, panel outdoors;
%                    vehicle = storage at parked-vehicle temperature (mid offset),
%                              panel on the roof at outdoor air.
%
% Panel model (horizontal panel, NASA irradiance is on a horizontal surface):
%   P = Wp * (G/1000) * (1 + gamma*(T_cell - 25)) * eta_bos
%   T_cell = T_out + (NOCT - 20)/800 * G
%   gamma = -0.40 %/C, NOCT = 45 C, eta_bos = 0.85 (soiling and wiring):
%   typical crystalline-silicon values, UNVERIFIED until a panel is chosen.
% Charger efficiency eta_chg = 0.85 (UNVERIFIED). Charger and electronics standby
% drain 0.1 mA (the step 3 design rule) and 0.5 mA, from the stored energy.
% LFP charging is blocked outside 0 to 45 C (Simpower IFR26650-33A datasheet).
% Supercapacitor floated at 2.3 V per cell (step 3: life 5 to 7 years in a cabinet).
% Weather files are reused from ../storage/data (downloaded by step 3).
% Units: SI except temperature in C and time in h where stated.

if exist('step4_output.txt','file'), delete('step4_output.txt'); end
diary('step4_output.txt');

%% Sites and weather (Nigeria only)
sites = struct('name', {'Ile-Ife','Lagos','Abuja','Maiduguri'}, ...
               'lat',  {7.47, 6.45, 9.06, 11.85}, 'lon', {4.56, 3.40, 7.49, 13.16});
nS = numel(sites); years = 2019:2023; nY = numel(years);
dataDir = fullfile(pwd, '..', 'storage', 'data');
if ~isfolder(dataDir), mkdir(dataDir); end
clim = struct('t',{},'T',{},'G',{});
for s = 1:nS
    t = datetime.empty(0,1); T = []; G = [];
    for y = years
        [ty, Ty, Gy] = get_power(sites(s), y, dataDir);
        t = [t; ty]; T = [T; Ty]; G = [G; Gy]; %#ok<AGROW>
    end
    clim(s).t = t;
    clim(s).T = fillmissing(T, 'linear', 'EndValues', 'nearest');
    clim(s).G = max(fillmissing(G, 'linear', 'EndValues', 'nearest'), 0);
end
k_mid = 23.5/900; tau_min = 30/log(4);     % step 3 vehicle rule, mid offset
caseNames = {'cabinet','vehicle_mid'}; nC = 2;

%% Parameters
pv.gamma = -0.004; pv.NOCT = 45; pv.eta_bos = 0.85; eta_chg = 0.85;
Wp = [0.1 0.25 0.5 1 2 5];  nW = numel(Wp);
drains = [0.1e-3 0.5e-3];
E0 = 0.5*120e-6*1700^2; eta_fb = 0.75; E_shock = E0/eta_fb;   % energy drawn per charge [J]

% Supercapacitor string (step 3 values)
sc.n = 6; sc.C = 100/6; sc.Vfloat = 6*2.3; sc.Vmin = 8.1;
sc.V1 = 9.73; sc.V3 = 12.33;                % string voltage for 1 and 3 charges (step 3)
sc.I20 = 260e-6; sc.Vr = 2.7; sc.Ccell = 100; sc.dTd = 10;
% LFP 4S IFR26650-33A
L.V = 13.2; L.Q = 3.3; L.E = L.V*L.Q*3600; L.sd25 = 0.035/730.5;
L.SOC20 = 20*E_shock/L.E;
fprintf('Energy drawn per shock charge: %.1f J. LFP reserve for 20 charges: %.1f %% SOC.\n', E_shock, 100*L.SOC20);
fprintf('Supercapacitor floated at %.1f V; 1 charge needs %.2f V, 3 charges need %.2f V.\n', sc.Vfloat, sc.V1, sc.V3);
fprintf('Drain power at 0.1 mA: %.2f mW (supercap string) and %.2f mW (LFP).\n\n', ...
        1e3*0.1e-3*sc.Vfloat, 1e3*0.1e-3*L.V);

%% Daily panel yield (for reference)
fprintf('Mean and worst daily energy from a 1 Wp panel [Wh/day]:\n');
for s = 1:nS
    P1 = pv_power(1, clim(s).G, clim(s).T, pv);
    d = sum(reshape(P1(1:24*floor(numel(P1)/24)), 24, []), 1);
    fprintf('  %-10s mean %.2f   worst day %.3f   worst 7-day mean %.3f\n', sites(s).name, ...
            mean(d), min(d), min(movmean(d, 7, 'Endpoints', 'discard')));
end
fprintf('\n');

%% Standby simulation, hour by hour, five years, starting full
TA = table();
for s = 1:nS
    Tout = clim(s).T; G = clim(s).G;
    for c = 1:nC
        if c == 1, Tst = Tout; else, Tst = cabin_temp(Tout, G, k_mid, tau_min); end
        for w = 1:nW
            Pch = eta_chg * pv_power(Wp(w), G, Tout, pv);          % [W] into storage
            for m = 1:numel(drains)
                V = sim_supercap(Pch, Tst, sc, drains(m));
                S = sim_lfp(Pch, Tst, L, drains(m));
                TA = [TA; table(string(sites(s).name), string(caseNames{c}), Wp(w), 1e3*drains(m), ...
                      100*mean(V >= sc.V3), 100*mean(V >= sc.V1), min(V), ...
                      100*mean(S >= L.SOC20), 100*min(S), ...
                      'VariableNames', {'Site','Case','Wp','drain_mA', ...
                      'SC_ready3_pct','SC_ready1_pct','SC_Vmin_V', ...
                      'LFP_ready20_pct','LFP_SOCmin_pct'})]; %#ok<AGROW>
            end
        end
    end
end
fprintf('Standby with solar: percent of hours ready (2019 to 2023), lowest stored level:\n');
disp(TA);
writetable(TA, 'step4_standby.csv');

% Smallest panel that is ready every hour
TM = table();
for s = 1:nS
    for c = 1:nC
        for m = 1:numel(drains)
            r = TA(TA.Site==sites(s).name & TA.Case==caseNames{c} & TA.drain_mA==1e3*drains(m), :);
            TM = [TM; table(string(sites(s).name), string(caseNames{c}), 1e3*drains(m), ...
                  first_wp(r.Wp, r.SC_ready3_pct), first_wp(r.Wp, r.LFP_ready20_pct), ...
                  'VariableNames', {'Site','Case','drain_mA','SC_min_Wp','LFP_min_Wp'})]; %#ok<AGROW>
        end
    end
end
fprintf('Smallest panel (from the swept sizes) that keeps storage ready 100 %% of hours\n');
fprintf('(NaN = none of the swept sizes):\n'); disp(TM);
writetable(TM, 'step4_min_panel.csv');

%% Recovery of the supercapacitor after a rescue
% Starts at Vmin (empty) at 00, 06, 12 and 18 h each day; counts hours until the
% string reaches the voltage for 3 charges from sun alone. Leakage is taken at the
% 3-charge voltage (an upper bound), with the 0.1 mA drain.
dE = 0.5*sc.C*(sc.V3^2 - sc.Vmin^2);
TRc = table();
H = 30*24;
for s = 1:nS
    for c = 1:nC
        Tout = clim(s).T; G = clim(s).G;
        if c == 1, Tst = Tout; else, Tst = cabin_temp(Tout, G, k_mid, tau_min); end
        Vc = sc.V3/sc.n;
        P_loss = sc.n*Vc*sc.I20*(Vc/sc.Vr).*2.^((Tst - 20)/sc.dTd) + 0.1e-3*sc.V3;   % [W]
        hr = hour(clim(s).t);
        starts = find(ismember(hr, [0 6 12 18])); starts = starts(starts + H <= numel(G));
        for w = 1:nW
            net = (eta_chg*pv_power(Wp(w), G, Tout, pv) - P_loss)*3600;   % [J per hour]
            cs = [0; cumsum(net)];
            h = nan(numel(starts),1);
            for j = 1:numel(starts)
                i0 = starts(j);
                k = find(cs(i0+1:i0+H) - cs(i0) >= dE, 1);
                if ~isempty(k), h(j) = k; end
            end
            fail = mean(isnan(h))*100;
            h(isnan(h)) = H;
            TRc = [TRc; table(string(sites(s).name), string(caseNames{c}), Wp(w), ...
                   median(h), prctile(h, 95), max(h), fail, 'VariableNames', ...
                   {'Site','Case','Wp','recover_h_median','recover_h_p95','recover_h_worst', ...
                    'not_in_30_days_pct'})]; %#ok<AGROW>
        end
    end
end
fprintf('Supercapacitor recovery from empty to 3 charges by sun alone [h]\n');
fprintf('(energy needed %.0f J; 720 h = not within 30 days):\n', dE);
disp(TRc);
writetable(TRc, 'step4_recovery.csv');

%% Figure
cols = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56];
f = figure('Color','w','Position',[60 60 1200 470]);
tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl); hold(ax1,'on'); box(ax1,'on'); grid(ax1,'on');
ax2 = nexttile(tl); hold(ax2,'on'); box(ax2,'on'); grid(ax2,'on');
for s = 1:nS
    for c = 1:nC
        ls = '-o'; if c == 2, ls = '--s'; end
        r = TA(TA.Site==sites(s).name & TA.Case==caseNames{c} & TA.drain_mA==0.1, :);
        plot(ax1, r.Wp, r.SC_ready3_pct, ls, 'Color', cols(s,:), 'LineWidth', 1.3, 'MarkerSize', 5, ...
             'DisplayName', sprintf('%s, %s', sites(s).name, strrep(caseNames{c}, '_mid', '')));
        q = TRc(TRc.Site==sites(s).name & TRc.Case==caseNames{c}, :);
        plot(ax2, q.Wp, q.recover_h_p95, ls, 'Color', cols(s,:), 'LineWidth', 1.3, 'MarkerSize', 5, ...
             'HandleVisibility', 'off');
    end
end
set([ax1 ax2], 'XScale', 'log', 'XLim', [0.08 6], 'XTick', Wp, 'FontName', 'Times New Roman', 'FontSize', 12);
ylim(ax1, [0 105]); set(ax2, 'YScale', 'log');
xlabel(ax1, 'Panel rating (W peak)'); ylabel(ax1, 'Hours with 3 shock charges stored (%)');
title(ax1, '(a) Supercapacitor kept ready by solar (0.1 mA drain)', 'FontWeight', 'normal');
xlabel(ax2, 'Panel rating (W peak)'); ylabel(ax2, 'Hours to refill to 3 charges, 95th percentile');
title(ax2, '(b) Supercapacitor refill after a rescue', 'FontWeight', 'normal');
lgd = legend(ax1, 'NumColumns', 4, 'Box', 'off'); lgd.Layout.Tile = 'south';
set(lgd, 'FontName', 'Times New Roman', 'FontSize', 11);
exportgraphics(f, 'fig_step4_solar.png', 'Resolution', 300);

diary off;
fprintf('Saved step4_output.txt, step4_standby.csv, step4_min_panel.csv, step4_recovery.csv, fig_step4_solar.png\n');
end

%% ------------------------------------------------------------------------
function P = pv_power(Wp, G, Tout, pv)
    Tcell = Tout + (pv.NOCT - 20)/800 .* G;
    P = Wp .* (G/1000) .* (1 + pv.gamma*(Tcell - 25)) * pv.eta_bos;
    P = max(P, 0);
end

function V = sim_supercap(Pch, T, sc, drain)
% Hourly: leakage decay (exact for the hour), minus drain energy, plus charge energy,
% capped at the float voltage.
    N = numel(Pch); V = zeros(N,1); v = sc.Vfloat;
    rate = sc.I20/(sc.Vr*sc.Ccell) .* 2.^((T - 20)/sc.dTd) * 3600;   % [1/h]
    for n = 1:N
        v = v*exp(-rate(n));
        E = 0.5*sc.C*v^2 - drain*v*3600 + Pch(n)*3600;
        v = min(sqrt(max(2*E/sc.C, 0)), sc.Vfloat);
        V(n) = v;
    end
end

function S = sim_lfp(Pch, T, L, drain)
% Hourly SOC: self-discharge (step 3 model), drain, solar charge only from 0 to 45 C.
    N = numel(Pch); S = zeros(N,1); soc = 1;
    sd = L.sd25 .* 2.^((T - 25)/10);
    ok = (T >= 0 & T <= 45);
    for n = 1:N
        soc = soc - sd(n) - drain/L.Q + ok(n)*Pch(n)*3600/L.E;
        soc = min(max(soc, 0), 1);
        S(n) = soc;
    end
end

function w = first_wp(Wp, pct)
    i = find(pct >= 100, 1);
    if isempty(i), w = NaN; else, w = Wp(i); end
end

function Tin = cabin_temp(Tout, G, k, tau_min)
    a = exp(-60/tau_min); Teq = Tout + k*G;
    Tin = zeros(size(Tout)); Tin(1) = Teq(1);
    for n = 2:numel(Tout), Tin(n) = Teq(n) + (Tin(n-1) - Teq(n))*a; end
end

function [t, T, G] = get_power(site, yr, dataDir)
% Same reader as step 3; downloads only if the file is missing.
    fname = fullfile(dataDir, sprintf('power_%s_%d.csv', strrep(site.name,'-',''), yr));
    if ~isfile(fname)
        url = sprintf(['https://power.larc.nasa.gov/api/temporal/hourly/point?' ...
              'parameters=T2M,ALLSKY_SFC_SW_DWN&community=RE&longitude=%.2f&latitude=%.2f' ...
              '&start=%d0101&end=%d1231&format=CSV&time-standard=LST'], site.lon, site.lat, yr, yr);
        fprintf('Downloading %s %d from NASA POWER ...\n', site.name, yr);
        txt = webread(url, weboptions('Timeout', 180, 'ContentType', 'text'));
        fid = fopen(fname, 'w'); fwrite(fid, txt, 'char'); fclose(fid);
    end
    lines = splitlines(string(fileread(fname)));
    iH = find(startsWith(strtrim(lines), "YEAR"), 1);
    hdr = strtrim(split(lines(iH), ","));
    M = readmatrix(fname, 'FileType', 'text', 'Delimiter', ',', 'NumHeaderLines', iH);
    M = M(all(~isnan(M(:,1:4)),2), :);
    col = @(nm) M(:, find(hdr == nm, 1));
    t = datetime(col("YEAR"), col("MO"), col("DY"), col("HR"), 0, 0);
    T = col("T2M"); G = col("ALLSKY_SFC_SW_DWN");
    T(T <= -998) = NaN; G(G <= -998) = NaN;
end
