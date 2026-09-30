clc;
clear;
close all;

filename = 'IEEE39_UFLS_Master_Input.xlsx';

tripGen = 9;

% % Module 1
% data = one_readInputData(filename);
% 
% % Module 2
% op = two_updateOpCond(data);
% op.tripGen = tripGen;
% 
% % Module 3
% Ybus = three_Ybus(data);
% 
% % Module 4
% result = four_newtonRaphson(data, op, Ybus);
% 
% % Module 5
% freq = five_frequencyResponse(data, op, result, Ybus, true);
% 
% % Module 6 - Load Shed value
% ufls = six_requiredLoadShedding(data, op, result, tripGen);
% 
% % MODULE 7: ADAPTIVE ZONE ALLOCATION
% zone = seven_zoneAllocation(data, freq, ufls);
% 
% % Module 8 - FVSI-based bus allocation
% [bus, zone] = eight_BusAllocation(data, op, result, zone);
% 
% % Module 9 - Feeder Allocation
% feeder = nine_feederAllocation(data, op, Ybus, bus, freq);
% 
% % MODULE 10: APPLY FEEDER SHEDDING
% post = ten_applyFeederShedding(data, op, result, Ybus, feeder);
% 
% % MODULE 11: POST-UFLS FREQUENCY RESPONSE
% result11 = eleven_frequencyExcursion(data, op, result, post);
% 
% % Module 12 - Export current contingency shedding scheme
% twelve_exportSheddingScheme(data, op, result, ufls, zone, bus, feeder, post, result11);

% testHour=12;
% 
% % Module 13 - Generator Vulnerability Assessment
% vulnerability = thirteen_generatorVulnerability(filename, testHour);

% MODULE 14: CONVENTIONAL vs ADAPTIVE UFLS
fprintf('\n\n============================================================\n');
fprintf(' RUNNING MODULE 14: CONVENTIONAL vs ADAPTIVE UFLS\n');
fprintf('============================================================\n');

comparison = fourteen_uflsComparison('IEEE39_UFLS_Master_Input.xlsx',12,9); 

% studyHour=12;
% tripGen = 9;
% % MODULE 15: SOLAR PENETRATION
% study15 = fifteen_solarPenetrationStudy(filename,tripGen);