%% Inicializacion
clear all, close all, clc

%% Parametros

carpeta = '2026_06_10_ia';   % Aca va el nombre de la carpeta con los .dat
archivo_dat = 'sec7';   % Available tests: sec1, sec3, sec5, sec6, sec7
%archivo_dat = '106_falla_reconf_corregido1_v05_q05';
archivo_param = 'parametros';

% Predicciones de la red: se busca '<archivo_dat>_predictions.xlsx' (o .xls)
% primero en la carpeta de datos y despues en la carpeta actual.
sufijo_pred = '_predictions';

% Muestra (de adq) donde empieza el tramo procesado que se le paso a la red.
% Solo se usa si no se puede alinear automaticamente con la senal 'esc'.
s_ini_pred = 301;

marcar_fallas = true;   % lineas verticales en los instantes de falla (senal esc)

% Figura y PDF de salida: '<archivo_dat>_fault_diagnosis.pdf'
carpeta_pdf = 'figures';   % carpeta donde se guarda el PDF
if ~exist(carpeta_pdf, 'dir'), mkdir(carpeta_pdf); end
ancho_cm = 18;          % tamano de la figura en el PDF [cm]
alto_cm  = 14;

run([carpeta, '/', archivo_param]);


%% Lectura de datos

inicio = 1; % Posicion de primera muestra
tMuestra = sampleTime * decimation;
m = plotName;                 % arreglo de celdas con los nombres
pathDatos = carpeta;
muestras_tot = muestras - inicio;

datfile = [carpeta, '/', archivo_dat, '.dat'];
datos_crudos = dlmread(datfile, '\n', 1, 0);   % se lee el archivo una sola vez
datos_crudos = datos_crudos(:).';               % se fuerza vector fila

for i = 1:nPlots
    adq.(m{i}) = datos_crudos((1+muestras*(i-1)):(muestras*i-1)) * 1/16384;
end

adq.t = 0 : tMuestra : (length(adq.(m{nPlots}))-1)*tMuestra;

save([carpeta, '/datos_', archivo_dat], 'adq')

%% Graficos (desactivados: solo se genera la figura final)
% figure
% fn = fieldnames(adq);
%
% N = nPlots;
%
% for i = 1:N
%     subplot(N,1,i), plot(adq.t, adq.(fn{i}));
%     xlim([min(adq.t) max(adq.t)])
%     ylabel(fn{i}, 'interpreter', 'none')
%     grid on
% end


%% Procesamiento de datos
s_ini = 470;

i_abc = [adq.i_a;  adq.i_b; -adq.i_a-adq.i_b];

%norma = sqrt( adq.i_d.^2 + adq.i_q.^2  );
%norma = mean(norma(50:250));
norma = sqrt( adq.i_alp_ref.^2 + adq.i_bet_ref.^2 ) * 40;

% bsxfun en lugar de i_abc.*(1./norma): la expansion implicita
% de una matriz 3xN por un vector 1xN no existe en R2015a
i_abc = bsxfun(@rdivide, i_abc, norma);

i_abc = i_abc(:, s_ini:s_ini+200);

% figure, plot(i_abc')
% xlim([0 200])

save([carpeta, '/datos_', archivo_dat, '_proc'], 'i_abc')


%% Velocidad, par y corrientes en por unidad
wr_pu = adq.wr;                         % velocidad del rotor [pu]
Te_pu = adq.i_q;                        % par en por unidad (= i_q en pu)

i_a_pu = adq.i_a;                       % corrientes de fase [pu]
i_b_pu = adq.i_b;
i_c_pu = -adq.i_a - adq.i_b;


%% Lectura de las predicciones de la red
archivo_pred = '';
candidatos = {fullfile(carpeta, [archivo_dat, sufijo_pred, '.xlsx']), ...
              fullfile(carpeta, [archivo_dat, sufijo_pred, '.xls']), ...
              [archivo_dat, sufijo_pred, '.xlsx'], ...
              [archivo_dat, sufijo_pred, '.xls']};
for k = 1:numel(candidatos)
    if exist(candidatos{k}, 'file') == 2
        archivo_pred = candidatos{k};
        break
    end
end
if isempty(archivo_pred)
    error('Prediction file %s%s.xlsx not found.', archivo_dat, sufijo_pred);
end
fprintf('Predictions read from: %s\n', archivo_pred);

[num, txt] = xlsread(archivo_pred);
encabezados = lower(strtrim(txt(1, :)));
col_fin  = find(strcmp(encabezados, 'end_sample'), 1);
col_pred = find(strcmp(encabezados, 'pred_class'), 1);
col_real = find(strcmp(encabezados, 'true_class'), 1);
if isempty(col_fin) || isempty(col_pred) || isempty(col_real)
    error('File %s must contain the columns end_sample, pred_class and true_class.', archivo_pred);
end

fin_ventana = num(:, col_fin);     % ultima muestra de cada ventana (base 0)
clase_pred  = num(:, col_pred);
clase_real  = num(:, col_real);

% Alineacion temporal: el primer cambio de la clase real coincide con el
% primer cambio de la senal esc (instante de la primera falla).
k_esc  = find(diff(adq.esc) ~= 0, 1) + 1;
w_real = find(clase_real ~= clase_real(1), 1);
if ~isempty(k_esc) && ~isempty(w_real)
    desfase = k_esc - fin_ventana(w_real);
    fprintf('Automatic alignment: window 0 starts at sample %d of adq.\n', desfase);
else
    desfase = s_ini_pred;
    fprintf('Alignment using s_ini_pred = %d.\n', desfase);
end

idx_pred = desfase + fin_ventana;              % indice en adq de cada prediccion
validos  = idx_pred >= 1 & idx_pred <= numel(adq.t);
t_pred   = adq.t(idx_pred(validos));
clase_pred = clase_pred(validos);
clase_real = clase_real(validos);

% Instantes de falla segun la senal esc
t_fallas = adq.t(find(diff(adq.esc) ~= 0) + 1);

% Rango temporal: desde la primera hasta la ultima prediccion de la red
t_ini_graf = t_pred(1);
t_fin_graf = t_pred(end);


%% Decodificacion de clases: que llaves corresponden a cada clase
% Numeracion: 1-6 simples, 7-21 dobles, 22-41 triples, en el orden
% Sa+, Sa-, Sb+, Sb-, Sc+, Sc- (combinaciones en orden lexicografico)
nombres_llaves = {'S_a^+','S_a^-','S_b^+','S_b^-','S_c^+','S_c^-'};
fase_llave     = [1 1 2 2 3 3];          % 1 = a, 2 = b, 3 = c
tabla_clases = {};
for k = 1:3
    C = nchoosek(1:6, k);
    for r = 1:size(C, 1)
        tabla_clases{end+1} = C(r, :); %#ok<SAGROW>
    end
end

% Colores: corrientes por fase; velocidad y par con colores distintos
col_fase = [1 0 0;        % fase a: rojo
            0 0.5 0;      % fase b: verde oscuro
            0 0 1];       % fase c: azul
col_wr = [0.49 0.18 0.56];   % velocidad: violeta
col_Tm = [0.93 0.55 0.00];   % par: naranja
col_gris = [0.4 0.4 0.4];

% Para cada instante de falla: llaves nuevas, rotulo y color
t_fallas = t_fallas(t_fallas >= t_ini_graf & t_fallas <= t_fin_graf);
rotulos_falla = cell(size(t_fallas));
color_falla = repmat(col_gris, numel(t_fallas), 1);
for f = 1:numel(t_fallas)
    k_ant = find(t_pred < t_fallas(f) - 2*tMuestra, 1, 'last');
    k_pos = find(t_pred > t_fallas(f) + 2*tMuestra, 1, 'first');
    if isempty(k_ant), c_ant = 0; else c_ant = clase_real(k_ant); end
    if isempty(k_pos), c_pos = 0; else c_pos = clase_real(k_pos); end
    llaves_ant = [];
    llaves_pos = [];
    if c_ant >= 1 && c_ant <= numel(tabla_clases), llaves_ant = tabla_clases{c_ant}; end
    if c_pos >= 1 && c_pos <= numel(tabla_clases), llaves_pos = tabla_clases{c_pos}; end
    nuevas = setdiff(llaves_pos, llaves_ant);
    if isempty(nuevas)
        rotulos_falla{f} = 'Fault';
    else
        % Cada llave con el color de la corriente de su fase
        color_falla(f, :) = col_fase(fase_llave(nuevas(1)), :);
        partes = cell(1, numel(nuevas));
        for n = 1:numel(nuevas)
            c = col_fase(fase_llave(nuevas(n)), :);
            partes{n} = sprintf('\\color[rgb]{%g %g %g}%s', c, nombres_llaves{nuevas(n)});
        end
        prefijo = sprintf('\\color[rgb]{%g %g %g}Fault in ', color_falla(f, :));
        rotulos_falla{f} = [prefijo, strjoin(partes, ', ')];
    end
end


%% Figura: velocidad, par, corrientes y prediccion
fuente = 'Times New Roman';
min_meseta = 10;   % ventanas minimas para rotular una meseta de F_s

fig = figure('Name', ['Results ', archivo_dat], 'Color', 'w', ...
             'Units', 'centimeters', 'Position', [2 2 ancho_cm alto_cm]);

ax(1) = subplot(4,1,1);
plot(adq.t, wr_pu, 'Color', col_wr, 'LineWidth', 1.2)
ylabel('\omega_r (pu)')
grid on

ax(2) = subplot(4,1,2);
plot(adq.t, Te_pu, 'Color', col_Tm, 'LineWidth', 1.2)
ylabel('T_m (pu)')
grid on

ax(3) = subplot(4,1,3);
plot(adq.t, i_a_pu, 'Color', col_fase(1,:), 'LineWidth', 1), hold on
plot(adq.t, i_b_pu, 'Color', col_fase(2,:), 'LineWidth', 1)
plot(adq.t, i_c_pu, 'Color', col_fase(3,:), 'LineWidth', 1)
ylabel('i_a, i_b, i_c (pu)')
grid on
% Escala vertical simetrica, con margen arriba para la leyenda
en_rango = adq.t >= t_ini_graf & adq.t <= t_fin_graf;
i_max = max(abs([i_a_pu(en_rango), i_b_pu(en_rango), i_c_pu(en_rango)]));
ylim([-1.15*i_max, 1.45*i_max])
legend('i_a', 'i_b', 'i_c', 'Location', 'northeast', 'Orientation', 'horizontal')

ax(4) = subplot(4,1,4);
stairs(t_pred, clase_real, '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.2), hold on
stairs(t_pred, clase_pred, 'k', 'LineWidth', 1.2)
ylabel('F_s')
xlabel('t (s)')
grid on
ylim([min([clase_real; clase_pred])-1, 1.25*max([clase_real; clase_pred])+1])
legend('F_s^* (true fault scenario)', 'F_s (predicted)', ...
       'Location', 'northwest', 'Orientation', 'horizontal')

linkaxes(ax, 'x')
xlim(ax(1), [t_ini_graf t_fin_graf])

% Rotulo con el numero de clase de la prediccion
% 1) Mesetas sostenidas (>= min_meseta ventanas) con un valor nuevo.
% 2) Toda clase predicha que no haya quedado rotulada (aunque sea un error
%    breve de la red) se rotula una vez, en su tramo mas largo.
% El estado sano inicial (clase 0 que empieza antes de la primera falla)
% no se rotula.
ini_tramo = [1; find(diff(clase_pred) ~= 0) + 1];
fin_tramo = [ini_tramo(2:end) - 1; numel(clase_pred)];
largo_tramo = fin_tramo - ini_tramo + 1;
valor_tramo = clase_pred(ini_tramo);

if isempty(t_fallas), t_primera = inf; else t_primera = t_fallas(1); end
t_ini_tramo = t_pred(ini_tramo);
sano_inicial = (valor_tramo == 0) & (t_ini_tramo(:) < t_primera);

rotular = false(size(ini_tramo));
ultimo_rotulo = NaN;
for r = 1:numel(ini_tramo)
    if ~sano_inicial(r) && largo_tramo(r) >= min_meseta && valor_tramo(r) ~= ultimo_rotulo
        rotular(r) = true;
        ultimo_rotulo = valor_tramo(r);
    end
end
valores = unique(valor_tramo(~sano_inicial));
for v = valores(:)'
    tramos_v = find(valor_tramo == v & ~sano_inicial);
    if ~any(rotular(tramos_v))
        [~, j] = max(largo_tramo(tramos_v));
        rotular(tramos_v(j)) = true;
    end
end

dx = 0.01 * (t_fin_graf - t_ini_graf);
for r = find(rotular)'
    text(t_pred(ini_tramo(r)) + dx, valor_tramo(r), num2str(valor_tramo(r)), ...
         'Parent', ax(4), 'VerticalAlignment', 'bottom', ...
         'FontName', fuente, 'FontSize', 10)
end

% Sin numeros de tiempo en los graficos superiores
for k = 1:3
    set(ax(k), 'XTickLabel', [])
end

% Letra identificatoria a la derecha de cada grafico
letras = {'(a)', '(b)', '(c)', '(d)'};
for k = 1:4
    text(1.02, 0.5, letras{k}, 'Parent', ax(k), 'Units', 'normalized', ...
         'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
         'FontName', fuente, 'FontSize', 11)
    set(ax(k), 'FontName', fuente)
end

% Lineas de falla en los 4 graficos (color de la fase en falla)
% y rotulo arriba del primero
if marcar_fallas
    for k = 1:4
        yl = get(ax(k), 'YLim');
        hold(ax(k), 'on')
        for f = 1:numel(t_fallas)
            plot(ax(k), [t_fallas(f) t_fallas(f)], yl, '--', 'Color', color_falla(f,:), ...
                 'LineWidth', 1.3, 'HandleVisibility', 'off')
        end
        set(ax(k), 'YLim', yl)
    end
    yl = get(ax(1), 'YLim');
    for f = 1:numel(t_fallas)
        plot(ax(1), t_fallas(f), yl(2), 'v', 'Color', color_falla(f,:), ...
             'MarkerFaceColor', color_falla(f,:), 'MarkerSize', 6, 'HandleVisibility', 'off')
        text(t_fallas(f), yl(2) + 0.12*diff(yl), rotulos_falla{f}, 'Parent', ax(1), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
             'FontName', fuente, 'FontSize', 11)
    end
end


%% Exportar a PDF: '<archivo_dat>_fault_diagnosis.pdf'
archivo_pdf = fullfile(carpeta_pdf, [archivo_dat, '_fault_diagnosis.pdf']);
set(fig, 'PaperUnits', 'centimeters', 'PaperSize', [ancho_cm alto_cm], ...
         'PaperPosition', [0 0 ancho_cm alto_cm], 'PaperPositionMode', 'manual');
print(fig, archivo_pdf, '-dpdf', '-painters');
fprintf('Figure saved to: %s\n', archivo_pdf);
