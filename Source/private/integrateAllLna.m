function ints = integrateAllLna(m, con, obs, opts)
n_obs = size(obs,1);

nes = vec([obs.ne]);
e_start = cumsum(nes) - nes + 1; % First index of an obs's events
e_end = cumsum(nes); % Last index of an obs's events

[tF, eve, fin, t_get] = collectObservations(m, con, obs);

if any([obs.Complex])
    ints = integrateLnaComp(m, con, tF, eve, fin, opts);
    
    % Distribute times for each observation
    ints = repmat(ints, n_obs,1);
    for i_obs = 1:n_obs
        if obs(i_obs).Complex
            % Only reveal time points in range of observation
            % Note: deval will still not throw an error outside this range
            ints(i_obs).t = [ints(i_obs).t(ints(i_obs).t < obs(i_obs).tF), obs(i_obs).tF];
        else
            % Evaluate all requested time points
            ints(i_obs).t = obs(i_obs).DiscreteTimes;
            ints(i_obs).x = ints(i_obs).x(ints(i_obs).t);
            ints(i_obs).u = ints(i_obs).u(ints(i_obs).t);
            ints(i_obs).y = ints(i_obs).y(ints(i_obs).t);
        end
    end
else
    error('Simple linear noise approximation not yet implemented')
    ints = integrateLnaSimp(m, con, tF, eve, fin, t_get, opts);
    
    % Distribute times for each observation
    ints = repmat(ints, n_obs,1);
    for i_obs = 1:n_obs
        % Select requested time points
        if numel(ints(i_obs).t) ~= numel(obs(i_obs).DiscreteTimes) % Saves time and memory if solution is large
            inds_i = lookupmember(ints(i_obs).t, obs(i_obs).DiscreteTimes);
            inds_i = inds_i(inds_i ~= 0);
            ints(i_obs).t = obs(i_obs).DiscreteTimes;
            ints(i_obs).x = ints(i_obs).x(inds_i);
            ints(i_obs).u = ints(i_obs).u(inds_i);
            ints(i_obs).y = ints(i_obs).y(inds_i);
        end
    end
end

% Distribute events for each observation
for i_obs = 1:n_obs
    current_events = ints(i_obs).ie >= e_start(i_obs) & ints(i_obs).ie <= e_end(i_obs);
    
    % Change ie to start at 1 for each observation
    ints(i_obs).ie = row(ints(i_obs).ie(current_events));
    ints(i_obs).ie = ints(i_obs).ie - e_start(i_obs) + 1;
    
    ints(i_obs).te = row(ints(i_obs).te(current_events));
    ints(i_obs).xe = ints(i_obs).xe(:,current_events);
    ints(i_obs).ue = ints(i_obs).ue(:,current_events);
    ints(i_obs).ye = ints(i_obs).ye(:,current_events);
end
