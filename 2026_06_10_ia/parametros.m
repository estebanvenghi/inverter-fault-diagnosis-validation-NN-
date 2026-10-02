% Datos adquisiciones
sampleTime = 1/1e3;  % Tiempo de muestreo
decimation = 1;      % Decimacion
muestras = 1300;     % Cantidad de muestras por plot
nPlots = 14;         % Cantidad de plot

% Datos scopes (arreglo de celdas, compatible con MATLAB R2015a)
plotName = cell(1, nPlots);
plotName{1}  = 'i_alp_ref';
plotName{2}  = 'i_bet_ref';
plotName{3}  = 'lam_alp_est';
plotName{4}  = 'lam_bet_est';
plotName{5}  = 'wr';
plotName{6}  = 'i_a';
plotName{7}  = 'i_b';
plotName{8}  = 'n_muestra';
plotName{9}  = 'esc';
plotName{10} = 'i_d';
plotName{11} = 'i_q';
plotName{12} = 'v_alp';
plotName{13} = 'v_bet';
plotName{14} = 'tita';
