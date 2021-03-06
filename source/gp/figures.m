%% Code used for producing figures

%% Import load and temperature data

data = importdata('load_input.csv',',');
times = data(:,1);
loads = data(:,2:end);
data = importdata('GP_pred_temp.csv',',');
temps = data(:,1:end);
data = load('smooth_temp_GP.mat', 'smoothed');
smooth_temps = data.smoothed;
clear data

%% Split into test and train

train = (loads(:,1) ~= 0);
test  = (loads(:,1) == 0);

%% For plotting

date_offset = 695421;

%% Plot zone 10

h = figure;
hold on;
train_times = times(train);
train_loads = loads(train,10);
plot (train_times((end-5000):(end-3700)) + date_offset, train_loads((end-5000):(end-3700)), '-', 'LineWidth', 1);
xlabel('Time');
ylabel('Load (Z10)');
%set(gca,'XTick',365)
datetick('x', 'mmm yyyy');
hold off;
getframe;  
save2pdf ('zone_10.pdf', h, 600);

%% Plot zone 9

h = figure;
hold on;
train_times = times(train);
train_loads = loads(train,9);
plot (train_times((end-4000):(end-3600)) + date_offset, train_loads((end-4000):(end-3600)), '-', 'LineWidth', 2);
xlabel('Time');
ylabel('Load (Z09)');
%set(gca,'XTick',365)
datetick('x', 'dd mmm yyyy');
hold off;
getframe;  
save2pdf ('zone_09.pdf', h, 600);

%% Remove means

means = mean(loads(train,:));
loads = loads - repmat(means, size(loads, 1), 1);

means_t = mean(temps(train,:));
temps = temps - repmat(means_t, size(temps, 1), 1);

means_st = mean(smooth_temps(train,:));
smooth_temps = smooth_temps - repmat(means_st, size(smooth_temps, 1), 1);

%% Scale the data

sds = std(loads(train,:));
loads = loads ./ repmat(sds, size(loads, 1), 1);

sds_t = std(temps(train,:));
temps = temps ./ repmat(sds_t, size(temps, 1), 1);

sds_st = std(smooth_temps(train,:));
smooth_temps = smooth_temps ./ repmat(sds_st, size(smooth_temps, 1), 1);

%% Plot zone 1 and temperature 9

h = figure;
hold on;
train_times = times(train);
train_loads = loads(train,1);
train_temps = temps(train,9);
[AX,H1,H2] = plotyy(train_times(1:250) + date_offset, train_loads(1:250), train_times(1:250) + date_offset, train_temps(1:250)); 
set(get(AX(1),'Ylabel'),'String','Load (Z01 standardised)'); 
set(get(AX(2),'Ylabel'),'String','Temperature (T09 standardised)');
set(H1,'LineStyle','-');
set(H2,'LineStyle','--');
set(H1,'LineWidth',2);
set(H2,'LineWidth',2);
xlabel('Time');
datetick(AX(1), 'x', 'dd mmm yyyy', 'keepticks');
datetick(AX(2), 'x', 'dd mmm yyyy', 'keepticks');
%set(AX(2), 'XTick',[])
hold off;
save2pdf ('gef_load_z01_t09_250.pdf', h, 600);

%% Main prediction code

for i = 1:1
  % Find the prediction regions in order
  searching_for_start = true;
  for j = 1:length(times)
    if searching_for_start
      if test(j)
        start_index = j-1;
        k = j + 1;
        searching_for_start = false;
        searching_for_end = true;
        while searching_for_end
          if (k > length(times)) || train(k) 
            searching_for_end = false;
            end_index = k;
          else
            k = k+1;
          end
        end
        % Found a region - try different models and combine to form
        % prediction
        lmls = zeros(size(temps, 2), 1);
        for t_i = 1:size(temps, 2)
          % Setup training and testing data splits
          if k < length(times)
            forecast = false;
            window = 500;
            train_times = [times((start_index - window):(start_index)) ; ...
                           times((end_index):(end_index + window))];
            train_loads = [loads((start_index - window):(start_index), i) ; ...
                           loads((end_index):(end_index + window), i)];
            train_temps = [temps((start_index - window):(start_index), t_i) ; ...
                           temps((end_index):(end_index + window), t_i)];
            train_smooth_temps = [smooth_temps((start_index - window):(start_index), t_i) ; ...
                           smooth_temps((end_index):(end_index + window), t_i)];
            test_times  = times((start_index+1):(end_index-1));
            test_temps  = temps((start_index+1):(end_index-1), t_i);
            test_smooth_temps  = smooth_temps((start_index+1):(end_index-1), t_i);
            test_indices = (start_index+1):(end_index-1);
            all_times = [times((start_index - window):(end_index + window))];
            all_temps = [temps((start_index - window):(end_index + window),:)];
          else
            forecast = true;
            window = 500;
            train_times = times((start_index - window):(start_index));
            train_loads = loads((start_index - window):(start_index), i);
            train_temps = temps((start_index - window):(start_index), t_i);
            train_smooth_temps = smooth_temps((start_index - window):(start_index), t_i);
            test_times  = times((start_index+1):(end_index-1));
            test_temps  = temps((start_index+1):(end_index-1), t_i);
            test_smooth_temps  = smooth_temps((start_index+1):(end_index-1), t_i);
            test_indices = (start_index+1):(end_index-1);
            all_times = [times((start_index - window):(end_index-1))];
            all_temps = [temps((start_index - window):(end_index-1), :)];
          end
          % Now do GP regression
          x = [train_times train_smooth_temps train_temps];
          x_test = [test_times test_smooth_temps test_temps];
          y = train_loads;
          
          if forecast
            if i == 9
              % This time series looks mostly random - use a simpler kernel
              x = x(:,1);
              x_test = x_test(:,1);
              covfunc = {@covSum, {@covSEiso, @covSEiso, @covPeriodic}};
              hyp.cov = [log(3) ; log(0.3) ; 
                         log(10) ; log(0.5) ; 
                         log(0.1) ; log(1) ; log(1)];
            else
              covfunc = @covElec01;
              % Equivalently - this kernel can be written in GPML
              % {@covSum, {{@covMask, {[1, 0, 0], @covSEiso}}, {@covMask, {[0, 1, 0], @covSEiso}},
              %            {@covProd, {{@covMask, {[0, 0, 1], @covSEiso}},
              %            {@covMask, {[1, 0, 0], @covPeriodic}}}}}
              hyp.cov = [log(2) ; log(0.3) ; 
                         log(0.5) ; log(0.5) ;
                         log(0.5) ; log(0.5) ;
                         log(0.1) ; log(1) ; log(1)];
            end
          else
            if i == 9
              % This time series looks mostly random - use a simpler kernel
              x = x(:,1);
              x_test = x_test(:,1);
              covfunc = {@covSum, {@covSEiso, @covSEiso, @covPeriodic}};
              hyp.cov = [log(3) ; log(0.3) ; 
                         log(10) ; log(0.5) ; 
                         log(0.1) ; log(1) ; log(1)];
            else
              covfunc = @covElec02;
              % Equivalently - this kernel can be written in GPML
              % {@covSum, {{@covMask, {[1, 0, 0], @covSEiso}}, {@covMask, {[0, 1, 0], @covSEiso}},
              %            {@covProd, {{@covMask, {[0, 0, 1], @covSEiso}},
              %                        {{@covMask, {[1, 0, 0], @covSEiso}}
              %                        {@covMask, {[1, 0, 0], @covPeriodic}}}}}
              hyp.cov = [log(2) ; log(0.3) ; 
                         log(0.5) ; log(0.5) ;
                         log(0.5) ; log(0.5) ;
                         log(2) ; log(0.5) ; 
                         log(0.1) ; log(1) ; log(1)];
            end
          end
          likfunc = @likGauss;
          if i == 9
            hyp.lik = log(0.8);
          else
            hyp.lik = log(0.2);
          end
          meanfunc = @meanZero;
          hyp.mean = [];
          hyp_opt = minimize(hyp, @gp, -1, @infExact, meanfunc, covfunc, likfunc, ...
                             x, y);
                           
          [m, ~] = gp(hyp_opt, @infExact, meanfunc, covfunc, likfunc, x, y, [x_test ; x]);

          if t_i == 1
            predictions = zeros(length(m), size(temps, 2));
          end
          predictions(:, t_i) = m(:);
          lmls(t_i) = -gp(hyp_opt, @infExact, meanfunc, covfunc, likfunc, x, y);

        end
        % Average predictions, plot and save
        weights = exp(lmls - max(lmls)) / sum(exp(lmls - max(lmls)));
        av_prediction = predictions * weights;
        
        % Plot
        
        best_i = find(weights == max(weights));
        h = figure;
        plot (train_times(1:(window+1)) + date_offset, train_loads(1:(window+1)), 'k-', 'LineWidth', 2);
%         [AX,H1,H2] = plotyy(train_times, train_loads, all_times, all_temps(:,best_i), 'plot');
        hold on
%         plot (train_times, av_prediction((length(test_times)+1):end), 'g');
        plot (test_times + date_offset, av_prediction(1:length(test_times)), 'r--', 'LineWidth', 2);
        legend('True load', 'GP prediction');
        if ~forecast
          plot (train_times((window+2):end) + date_offset, train_loads((window+2):end), 'k-', 'LineWidth', 2);
        end
        plot ([min(test_times) + date_offset, min(test_times) + date_offset], [-1, 3], 'k--');
        plot ([max(test_times) + date_offset, max(test_times) + date_offset], [-1, 3], 'k--');
        xlim ([times(start_index+1)-5 + date_offset, times(end_index-1)+5 + date_offset]);
        ylim ([-1, 3]);
        xlabel('Time')
        ylabel('Load (Z01 standardised)')
        datetick('x', 'dd mmm yyyy', 'keeplimits');
        getframe;  
        hold off
%         set(get(AX(1),'xlim'),[times(start_index+1)-5, times(end_index-1)+5]);
%         set(get(AX(2),'xlim'),[times(start_index+1)-5, times(end_index-1)+5]);
%         set(get(AX(1),'Ylabel'),'String','Load') 
%         set(get(AX(2),'Ylabel'),'String','Temperature') 
        getframe;  
        save2pdf ('load_pred.pdf', h, 600);
        h = figure;
        plot (all_times + date_offset, all_temps(:,best_i), 'k-', 'LineWidth', 2);
        legend('Temperature');
        hold on;
        plot ([min(test_times) + date_offset, min(test_times) + date_offset], [1, -2.5], 'k--');
        plot ([max(test_times) + date_offset, max(test_times) + date_offset], [1, -2.5], 'k--');
        xlim ([times(start_index+1)-5 + date_offset, times(end_index-1)+5 + date_offset]);
        %ylim ([1, -2.5]);
        xlabel('Time')
        ylabel('Temperature (T06 standardised)')
        datetick('x', 'dd mmm yyyy', 'keeplimits');
        getframe;  
        
        save2pdf ('best_temp.pdf', h, 600);

        % Save

        loads(test_indices, i) = av_prediction(1:length(test_indices));
        
        % Now plot obviously bad examples
        
        
        
        % Wait so we can see what's happening
        pause (1);
        break;
      end
    elseif train(j)
      searching_for_start = true;
    end
  end
end

%% Now plot obviously bad predictions

t_i = best_i;

train_times = [times((start_index - window):(start_index)) ; ...
               times((end_index):(end_index + window))];
train_loads = [loads((start_index - window):(start_index), i) ; ...
               loads((end_index):(end_index + window), i)];
train_temps = [temps((start_index - window):(start_index), t_i) ; ...
               temps((end_index):(end_index + window), t_i)];
train_smooth_temps = [smooth_temps((start_index - window):(start_index), t_i) ; ...
               smooth_temps((end_index):(end_index + window), t_i)];
test_times  = times((start_index+1):(end_index-1));
test_temps  = temps((start_index+1):(end_index-1), t_i);
test_smooth_temps  = smooth_temps((start_index+1):(end_index-1), t_i);
test_indices = (start_index+1):(end_index-1);
all_times = [times((start_index - window):(end_index + window))];
all_temps = [temps((start_index - window):(end_index + window),:)];

x = [train_times train_smooth_temps train_temps];
x_test = [test_times test_smooth_temps test_temps];
y = train_loads;

meanfunc = @meanZero;
hyp.mean = [];
covfunc = {@covMask, {[1, 0, 0], @covSEiso}};
hyp.cov = [0;0];
hyp_opt = minimize(hyp, @gp, -100, @infExact, meanfunc, covfunc, likfunc, ...
                 x, y);

[m, ~] = gp(hyp_opt, @infExact, meanfunc, covfunc, likfunc, x, y, [x_test ; x]);

h = figure;
plot (train_times(1:(window+1)) + date_offset, train_loads(1:(window+1)), 'k-', 'LineWidth', 2);
hold on
plot (test_times + date_offset, m(1:length(test_times)), 'r--', 'LineWidth', 2);
legend('True load', 'GP prediction');
if ~forecast
  plot (train_times((window+2):end) + date_offset, train_loads((window+2):end), 'k-', 'LineWidth', 2);
end
plot ([min(test_times) + date_offset, min(test_times) + date_offset], [-1, 3], 'k--');
plot ([max(test_times) + date_offset, max(test_times) + date_offset], [-1, 3], 'k--');
xlim ([times(start_index+1)-5 + date_offset, times(end_index-1)+5 + date_offset]);
ylim ([-1, 3]);
xlabel('Time')
ylabel('Load (Z01 standardised)')
datetick('x', 'dd mmm yyyy', 'keeplimits');
getframe;  
hold off
getframe;  
save2pdf ('load_pred_SE.pdf', h, 600);

%% Now plot obviously bad predictions v2

t_i = best_i;

train_times = [times((start_index - window):(start_index)) ; ...
               times((end_index):(end_index + window))];
train_loads = [loads((start_index - window):(start_index), i) ; ...
               loads((end_index):(end_index + window), i)];
train_temps = [temps((start_index - window):(start_index), t_i) ; ...
               temps((end_index):(end_index + window), t_i)];
train_smooth_temps = [smooth_temps((start_index - window):(start_index), t_i) ; ...
               smooth_temps((end_index):(end_index + window), t_i)];
test_times  = times((start_index+1):(end_index-1));
test_temps  = temps((start_index+1):(end_index-1), t_i);
test_smooth_temps  = smooth_temps((start_index+1):(end_index-1), t_i);
test_indices = (start_index+1):(end_index-1);
all_times = [times((start_index - window):(end_index + window))];
all_temps = [temps((start_index - window):(end_index + window),:)];

x = [train_times train_smooth_temps train_temps];
x_test = [test_times test_smooth_temps test_temps];
y = train_loads;

meanfunc = @meanZero;
hyp.mean = [];
covfunc = {@covSum, {{@covMask, {[1, 0, 0], @covSEiso}}, {@covMask, {[0, 1, 0], @covSEiso}}, {@covMask, {[0, 0, 1], @covSEiso}}}};
hyp.cov = [0;0;0;0;0;0];
%covfunc = {@covSEard};
%hyp.cov = [0;1;1;0];
hyp_opt = minimize(hyp, @gp, -100, @infExact, meanfunc, covfunc, likfunc, ...
                 x, y);

[m, ~] = gp(hyp_opt, @infExact, meanfunc, covfunc, likfunc, x, y, [x_test ; x]);

h = figure;
plot (train_times(1:(window+1)) + date_offset, train_loads(1:(window+1)), 'k-', 'LineWidth', 2);
hold on
plot (test_times + date_offset, m(1:length(test_times)), 'r--', 'LineWidth', 2);
legend('True load', 'GP prediction');
if ~forecast
  plot (train_times((window+2):end) + date_offset, train_loads((window+2):end), 'k-', 'LineWidth', 2);
end
plot ([min(test_times) + date_offset, min(test_times) + date_offset], [-1, 3], 'k--');
plot ([max(test_times) + date_offset, max(test_times) + date_offset], [-1, 3], 'k--');
xlim ([times(start_index+1)-5 + date_offset, times(end_index-1)+5 + date_offset]);
ylim ([-1, 3]);
xlabel('Time')
ylabel('Load (Z01 standardised)')
datetick('x', 'dd mmm yyyy', 'keeplimits');
getframe;  
hold off
getframe;  
save2pdf ('load_pred_SEard.pdf', h, 600);

%% Draw from kernel

covfunc = @covElec02;
hyp.cov = [log(2) ; log(0.3) ; 
         log(0.5) ; log(0.5) ;
         log(0.5) ; log(0.5) ;
         log(2) ; log(0.5) ; 
         log(0.4) ; log(1) ; log(1)];
K = feval(covfunc, hyp.cov, [x_test]);
K = K + 10e-5*max(max(K));
m = chol(K)' * randn(size(K,1),1);

h = figure;
plot (test_times + date_offset, m(1:length(test_times)), 'b-', 'LineWidth', 1);
hold on
xlim ([min(test_times) + date_offset, max(test_times) + date_offset]);
xlabel('')
ylabel('')
set(gca, 'XTick', []);
getframe;  
hold off
getframe;  
save2pdf ('fancy_kernel_draw4.pdf', h, 600);