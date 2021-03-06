function int = integrateCurvComp(m, con, tF, eve, fin, opts)
% Constants
nx = m.nx;
nu = m.nu;
ny = m.ny;
nk = m.nk;
ns = m.ns;
nq = con.nq;
nh = con.nh;
nTk = sum(opts.UseParams);
nTs = sum(opts.UseSeeds);
nTq = sum(opts.UseInputControls);
nTh = sum(opts.UseDoseControls);
nT  = nTk + nTs + nTq + nTh;

dxdTStart = nx+1;
dxdTEnd   = nx+nx*nT;
d2xdT2Start = nx+nx*nT+1;
d2xdT2End   = nx+nx*nT+nx*nT*nT;
normalized = opts.Normalized;
T = collectActiveParameters(m, con, opts.UseParams, opts.UseSeeds, {opts.UseInputControls}, {opts.UseDoseControls});

dkdT = sparse(find(opts.UseParams), 1:nTk, 1, nk, nT);
if normalized
    dkdT_maybe_normalized = bsxfun(@times, dkdT, row(T));
else
    dkdT_maybe_normalized = dkdT;
end

uqUseInputControls = linearslicer([nu,nq], true(nu,1), opts.UseInputControls);

y = m.y;
u = con.u;
dudq = con.dudq;
d2udq2 = con.d2udq2;
dydx = m.dydx;
dydu = m.dydu;
dydk = m.dydk;
d2ydx2 = m.d2ydx2;
d2ydu2 = m.d2ydu2;
d2ydk2 = m.d2ydk2;
d2ydudx = m.d2ydudx;
d2ydkdx = m.d2ydkdx;
d2ydkdu = m.d2ydkdu;

% Construct system
[der, jac, del] = constructSystem();

if ~con.SteadyState
    order = 2;
    ic = extractICs(m,con,opts,order);
else
    % Run to steady-state first
    ic = steadystateCurv(m, con, opts);
end

% Integrate [f; dfdT; d2fdT2] over time
sol = accumulateOdeFwdComp(der, jac, 0, tF, ic, con.Discontinuities, 1:nx, opts.RelTol, opts.AbsTol(1:nx+nx*nT+nx*nT*nT), del, eve, fin);

% Work down
int.Type = 'Integration.Curvature.Complex';
int.Name = [m.Name ' in ' con.Name];

int.x_names = vec({m.States.Name});
int.u_names = vec({m.Inputs.Name});
int.y_names = vec({m.Outputs.Name});
int.k_names = vec({m.Parameters.Name});
int.s_names = vec({m.Seeds.Name});

int.nx = nx;
int.ny = m.ny;
int.nu = m.nu;
int.nk = m.nk;
int.ns = m.ns;
int.nq = con.nq;
int.nh = con.nh;
int.k = m.k;
int.s = con.s;
int.q = con.q;
int.h = con.h;

int.dydx = m.dydx;
int.dydu = m.dydu;
int.dydk = m.dydk;

int.nT = nT;
int.UseParams = opts.UseParams;
int.UseSeeds = opts.UseSeeds;
int.UseInputControls = opts.UseInputControls;
int.UseDoseControls = opts.UseDoseControls;

int.t = sol.x;
int.x = @(t)evaluate_state(sol, t);
int.u = con.u;
int.y = @(t)evaluate_output(sol, t);

int.dxdT = @(t)evaluate_state_sensitivity(sol, t);
int.dudT = @evaluate_input_sensitivity;
int.dydT = @(t)evaluate_output_sensitivity(sol, t);

int.d2xdT2 = @(t)evaluate_state_curvature(sol, t);
int.d2udT2 = @evaluate_input_curvature;
int.d2ydT2 = @(t)evaluate_output_curvature(sol, t);

nte = numel(sol.ie);
int.ie = sol.ie;
int.te = sol.xe;
int.xe = sol.ye(1:nx,:);
int.ue = u(int.te);
int.ye = y(int.te, int.xe, int.ue);

int.dxedT = sol.ye(dxdTStart:dxdTEnd,:);
int.duedT = zeros(nu*nT,nte);
int.dyedT = zeros(ny*nT,nte);
int.d2xedT2 = sol.ye(d2xdT2Start:d2xdT2End,:);
int.d2uedT2 = zeros(nu*nT*nT,nte);
int.d2yedT2 = zeros(ny*nT*nT,nte);
for it = 1:nte
    duedq_i = dudq(int.te(it)); % u_q
    duedq_i = duedq_i(:,opts.UseInputControls); % u_Q
    duedT_i = [sparse(nu,nTk+nTs), reshape(duedq_i, nu,nTq), sparse(nu,nTh)]; % u_Q -> u_T
    int.duedT(:,it) = vec(duedT_i); % u_T -> uT_

    dyedx_i = dydx(int.te(it), int.xe(:,it), int.ue(:,it)); % y_x
    dyedu_i = dydu(int.te(it), int.xe(:,it), int.ue(:,it)); % y_u
    dyedk_i = dydk(int.te(it), int.xe(:,it), int.ue(:,it)); % y_k
    dxedT_i = reshape(int.dxedT(:,it), nx,nT); % xT_ -> x_T
    int.dyedT(:,it) = vec(dyedx_i * dxedT_i + dyedu_i * duedT_i + dyedk_i * dkdT); % y_x * x_T + y_u * u_T -> y_T -> yT_
    
    d2uedq2_i = d2udq2(int.te(it)); % uq_q
    d2uedq2_i = d2uedq2_i(uqUseInputControls,opts.UseInputControls); % uQ_Q
    d2uedT2_i = [sparse(nu*(nTk+nTs),nT);
                sparse(nu*nTq,nTk+nTs), d2uedq2_i, sparse(nu*nTq,nTh);
                sparse(nu*nTh,nT)]; % uT_T
    d2uedT2_i = reshape(d2uedT2_i, nu,nT*nT); % uT_T -> u_TT
    int.d2uedT2(:,it) = vec(d2uedT2_i);
    
    d2xedT2_i = reshape(int.d2xedT2(:,it), nx,nT*nT); % xT_T -> x_TT
    d2yedx2_i = d2ydx2(int.te(it), int.xe(:,it), int.ue(:,it)); % yx_x
    d2yedu2_i = d2ydu2(int.te(it), int.xe(:,it), int.ue(:,it)); % yx_x
    d2yedudx_i = d2ydudx(int.te(it), int.xe(:,it), int.ue(:,it)); % yx_u
    d2yedk2_i = d2ydk2(int.te(it), int.xe(:,it), int.ue(:,it));
    d2yedkdx_i = d2ydkdx(int.te(it), int.xe(:,it), int.ue(:,it));
    d2yedkdu_i = d2ydkdu(int.te(it), int.xe(:,it), int.ue(:,it));
    temp1e = d2yedx2_i * dxedT_i; % yx_x * x_T -> yx_T
    temp1e = reshape(spermute132(temp1e, [ny,nx,nT], [ny*nT,nx]) * dxedT_i, ny,nT*nT); % (yx_T -> yT_x) * x_T -> yT_T -> y_TT
    temp2e = d2yedu2_i * duedT_i; % yu_u * u_T -> yu_T
    temp2e = reshape(spermute132(temp2e, [ny,nu,nT], [ny*nT,nu]) * duedT_i, ny,nT*nT); % (yu_T -> yT_u) * u_T -> yT_T -> y_TT
    temp3e = d2yedk2_i * dkdT; % yk_k * k_T -> yk_T
    temp3e = reshape(spermute132(temp3e, [ny,nk,nT], [ny*nT,nk]) * dkdT, ny,nT*nT); % (yk_T -> yT_k) * k_T -> yT_T -> y_TT
    temp4e = d2yedudx_i * duedT_i; % yx_u * u_T -> yx_T
    temp4e = spermute132(temp4e, [ny,nx,nT], [ny*nT,nx]) * dxedT_i; % (yx_T -> yT_x) * x_T -> yT_T
    temp4e = reshape(temp4e + spermute132(temp4e, [ny,nT,nT], [ny*nT,nT]), ny,nT*nT); % yT_T + (yT_T -> yT_T) -> yT_T -> y_TT
    temp5e = d2yedkdx_i * dkdT; % yx_k * k_T -> yx_T
    temp5e = spermute132(temp5e, [ny,nx,nT], [ny*nT,nx]) * dxedT_i; % (yx_T -> yT_x) * x_T -> yT_T
    temp5e = reshape(temp5e + spermute132(temp5e, [ny,nT,nT], [ny*nT,nT]), ny,nT*nT); % yT_T + (yT_T -> yT_T) -> yT_T -> y_TT
    temp6e = d2yedkdu_i * dkdT; % yu_k * k_T -> yu_T
    temp6e = spermute132(temp6e, [ny,nu,nT], [ny*nT,nu]) * duedT_i; % (yu_T -> yT_u) * u_T -> yT_T
    temp6e = reshape(temp6e + spermute132(temp6e, [ny,nT,nT], [ny*nT,nT]), ny,nT*nT); % yT_T + (yT_T -> yT_T) -> yT_T -> y_TT
    
    % Note d2kdT2 is zero, so dydk_i * d2kdT2 term is zero
    d2yedT2 = dyedx_i * d2xedT2_i + dyedu_i * d2uedT2_i + temp1e + temp2e + temp3e + temp4e + temp5e + temp6e;
    int.d2yedT2(:,it) = vec(d2yedT2);
end

if normalized
    % Normalize events
    [int.dxedT, int.d2xedT2] = normalizeDerivatives(T, int.dxedT, int.d2xedT2);
    [int.duedT, int.d2uedT2] = normalizeDerivatives(T, int.duedT, int.d2uedT2);
    [int.dyedT, int.d2yedT2] = normalizeDerivatives(T, int.dyedT, int.d2yedT2);
end

int.sol = sol;

% End of function
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% The system for integrating f and dfdT and d2fdT2 %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function [der, jac, del] = constructSystem()
        
        IT = speye(nT);
        IT2 = speye(nT*nT);
        TPermuteInd = vec(permute(reshape(1:nx*nT*nT, nx,nT,nT), [1,3,2])); % indexes that permute the last two T of fTT_
        fkUseParams = linearslicer([nx,nk], true(nx,1), opts.UseParams);
        dhUseDoseControls = linearslicer([ns,nh], true(ns,1), opts.UseDoseControls);

        f       = m.f;
        dfdx    = m.dfdx;
        dfdu    = m.dfdu;
        dfdk    = m.dfdk;
        dfdT    = @dfdTSub;
        d2fdx2  = m.d2fdx2;
        d2fdT2  = @d2fdT2Sub;
        d2fdudx = m.d2fdudx;
        d2fdTdx = @d2fdTdxSub;
        d2fdxdT = @d2fdxdTSub;
        d2fdu2  = m.d2fdu2;
        d2fdk2  = m.d2fdk2;
        d2fdudk = m.d2fdudk;
        d2fdkdx = m.d2fdkdx;
        
        der = @derivative;
        jac = @jacobian;
        del = @delta;
        
        % Derivative of [x; dxdT; d2xdT2] with respect to time
        function val = derivative(t, joint)
            ui = u(t);            
            xi = joint(1:nx);
            dxdT = reshape(joint(dxdTStart:dxdTEnd), nx,nT); % xT_ -> x_T
            d2xdT2 = reshape(joint(d2xdT2Start:d2xdT2End), nx,nT*nT); % xTT_ -> x_TT
            
            % Derivative of dxdT
            % dxdTdot = dfdx *{x.x} dxdT + dxdT
            dxdTdot = dfdx(t,xi,ui) * dxdT + dfdT(t,xi,ui); % f_x * x_T + f_T -> f_T
            
            % Derivative of d2xdT2
            % d2xdT2dot = dfdx *{x.x} d2xdT1dT2 + (d2fdx2 *{x.x} dxdT2) *{x.x} dxdT1 + d2fdT2dx *{x.x} dxdT1 + d2fdT1dx *{x.x} dxdT2 + d2fdT1dT2
            temp = sparse(d2fdxdT(t,xi,ui) * dxdT); % fT_x * x_T -> fT_T
            temp = temp + spermute132(temp, [nx,nT,nT], [nx*nT,nT]); % fT_T + (fT_T -> fT_T) -> fT_T
            d2xdT2dot = sparse(d2fdx2(t,xi,ui) * dxdT); % fx_x * x_T -> fx_T
            d2xdT2dot = spermute132(d2xdT2dot, [nx,nx,nT], [nx*nT,nx]); % fx_T -> fT_x
            d2xdT2dot = sparse(d2xdT2dot * dxdT); % fT_x * x_T -> fT_T
            d2xdT2dot = reshape(dfdx(t,xi,ui) * d2xdT2, nx*nT,nT) + d2xdT2dot + temp + d2fdT2(t,xi,ui); % (f_x * x_TT -> f_TT -> fT_T) + fT_T + fT_T + fT_T -> fT_T
            
            % Combine
            val = [f(t,xi,ui); vec(dxdTdot); vec(d2xdT2dot)];
        end
        
        % Jacobian of [x; dxdT; d2xdT2] derivative
        function val = jacobian(t, joint)
            ui = u(t);            
            xi = joint(1:nx); % x_
            dxdT = reshape(joint(dxdTStart:dxdTEnd), nx,nT); % x_T
            d2xdT2 = reshape(joint(d2xdT2Start:d2xdT2End), nx,nT*nT); % xTT_ -> x_TT
            
            % Compute d/dx(dfdT)
            d2fdxdT_val = sparse(d2fdx2(t,xi,ui) * dxdT) + d2fdTdx(t,xi,ui); % fx_T
            d2fdxdT_val = spermute132(d2fdxdT_val, [nx,nx,nT], [nx*nT,nx]);
            
            % Compute d/dx(d2fdT2)
            % This part is very computationally expensive and for unknown
            % reasons does not matter at all. Therefore, it is set to zero.
            % The computational expense mostly comes from sparse*full
            % yielding full because Matlab does not understand how sparse
            % these things really are.
            d3fdxdTdT_val = sparse(nx*nT*nT,nx);
            
            % Real computation
            %temp = sparse(d3fdxdTdx(t,x,u) * dxdT); % fxT_x * x_T -> fxT_T
            %temp = temp + spermute132(temp, [nx*nx,nT,nT], [nx*nx*nT,nT]); % fxT_T + (fxT_T -> fxT_T) -> fxT_T
            %d3fdxdTdT_val = sparse(d3fdx3(t,x,u) * dxdT); % fxx_x * x_T -> fxx_T
            %d3fdxdTdT_val = spermute132(d3fdxdTdT_val, [nx*nx,nx,nT], [nx*nx*nT,nx]); % fxx_T -> fxT_x
            %d3fdxdTdT_val = sparse(d3fdxdTdT_val * dxdT); % fxT_x * x_T -> fxT_T
            %d3fdxdTdT_val = reshape(df2dx2(t,x,u) * d2xdT2, nx*nx*nT,nT) + d3fdxdTdT_val + temp + d3fdxdTdT; % ((fx_x * x_TT -> fx_TT) -> fxT_T) + fxT_T + fxT_T + fxT_T -> fxT_T
            
            % Compute d/dxdT(d2fdT2)
            % d/dxdT(d2fdT2) = (d2fdx2 *{x.x} dxdT2) * IT1 + (d2fdx2 *{x.x} dxdT1) * IT2 + d2fdT2dx * IT1 + d2fdT1dx * IT2
            d3fddxdTT2 = sparse(d2fdx2(t,xi,ui) * dxdT); % fx_x * x_T -> fx_T
            d3fddxdTT2 = spermute132(d3fddxdTT2, [nx,nx,nT], [nx*nT,nx]); % fx_T -> fT_x
            d3fddxdTT2 = d3fddxdTT2 + d2fdxdT(t,xi,ui); % fT_x + fT_x -> fT_x
            d3fddxdTT2 = kron(IT, d3fddxdTT2); % T_T kron fT_x -> fTT_xT
            d3fddxdTT2 = d3fddxdTT2 + d3fddxdTT2(TPermuteInd,:); % fTT_xT + (fTT_xT -> fTT_xT) -> fTT_xT
            
            % Combine
            val = [dfdx(t,xi,ui),   sparse(nx,nx*nT),      sparse(nx,nx*nT*nT);
                   d2fdxdT_val,   kron(IT, dfdx(t,xi,ui)), sparse(nx*nT,nx*nT*nT);
                   d3fdxdTdT_val, d3fddxdTT2,            kron(IT2, dfdx(t,xi,ui))];
        end
        
        % Dosing
        function val = delta(t, joint)
            val = collectDoseImpact(m, con, t, 2, opts.UseParams, opts.UseSeeds, opts.UseInputControls, opts.UseDoseControls);
        end
        
        % Modifies dfdk to relate only to the parameters of interest
        function val = dfdTSub(t, x, u)
            val = dfdk(t,x,u); % f_k
            dudq_i = dudq(t); % u_q
            dfdTq = dfdu(t,x,u) * dudq_i(:,opts.UseInputControls); % f_u * (u_q -> u_Q) -> f_Q
            val = [val(:,opts.UseParams), sparse(nx,nTs), dfdTq, sparse(nx,nTh)]; % f_T
        end
        
        % Modifies d2fdkdk to relate only to the parameters of interest
        function val = d2fdT2Sub(t, x, u)
            val = d2fdk2(t,x,u); % fk_k
            
            dudq_i = dudq(t); % u_q
            dudq_i = dudq_i(:,opts.UseInputControls); % u_q -> u_Q
            
            d2udQ2_i = d2udq2(t); % uq_q
            d2udQ2_i = reshape(d2udQ2_i(uqUseInputControls,opts.UseInputControls), [nu,nTq*nTq]); % uq_q -> uQ_Q -> u_QQ
            
            d2fdq2 = d2fdu2(t,x,u) * dudq_i; % fu_u * u_Q -> fu_Q
            d2fdq2 = spermute132(d2fdq2, [nx,nu,nTq], [nx*nTq,nu]) * dudq_i + reshape(dfdu(t,x,u) * d2udQ2_i, [nx*nTq,nTq]); % ((fu_Q -> fQ_u) * u_Q -> fQ_Q) + (f_u * u_QQ -> f_QQ -> fQ_Q) -> fQ_Q
            
            d2fdqdk = d2fdudk(t,x,u); % fk_u
            d2fdqdk = d2fdqdk(fkUseParams,:) * dudq_i; % (fk_u -> fK_u) * u_Q -> fK_Q
            
            val = [val(fkUseParams,opts.UseParams),                  sparse(nx*nTk, nTs), d2fdqdk, sparse(nx*nTk,nTh);
                   sparse(nx*nTs, nTk+nTs+nTq+nTh);
                   spermute132(d2fdqdk, [nx,nTk,nTq], [nx*nTq,nTk]), sparse(nx*nTq, nTs), d2fdq2,  sparse(nx*nTq,nTh);
                   sparse(nx*nTh, nTk+nTs+nTq+nTh)];
               % fT_T
        end
        
        % Modifies d2fdkdx to relate only to the parameters of interest
        function val = d2fdTdxSub(t, x, u)
            val = d2fdkdx(t,x,u); % fx_k
            d2fdqdx = d2fdudx(t,x,u) * dudq(t); % fx_u * u_q -> fx_q
            val = [val(:,opts.UseParams), sparse(nx*nx, nTs), d2fdqdx(:,opts.UseInputControls), sparse(nx*nx,nTh)]; % fx_T
        end
        
        % Modifies d2fdxdk to relate only to the parameters of interest
        function val = d2fdxdTSub(t, x, u)
            val = spermute132(d2fdTdx(t,x,u), [nx,nx,nT], [nx*nT,nx]); % fx_T -> fT_x
        end
    end

    function val = evaluate_state(sol, t)
        val = devals(sol, t, 1:nx);
    end

    function val = evaluate_output(sol, t)
        val = y(t, devals(sol, t, 1:nx), u(t));
    end

    function val = evaluate_state_sensitivity(sol, t)
        val = devals(sol, t, dxdTStart:dxdTEnd); % xT_t
        if normalized
            val = normalizeDerivatives(T, val);
        end
    end

    function val = evaluate_input_sensitivity(t)
        val = evaluate_input_sensitivity_nonnormalized(t);
        
        if normalized
            val = normalizeDerivatives(T, val);
        end
    end

    function val = evaluate_input_sensitivity_nonnormalized(t)
        nt = numel(t);
        
        val = zeros(nu*nT,nt);
        for i = 1:nt
            dudq_i = dudq(t(i)); % u_q
            dudq_i = dudq_i(:,opts.UseInputControls); % u_Q
            dudT = [sparse(nu,nTk+nTs), reshape(dudq_i, nu,nTq), sparse(nu,nTh)]; % u_Q -> u_T
            val(:,i) = vec(dudT); % u_Q -> u_T -> uT_
        end
    end

    function val = evaluate_output_sensitivity(sol, t)
        nt = numel(t);
        
        val = zeros(ny*nT,nt);
        for i = 1:nt
            x_i = deval(sol, t(i), 1:nx); % x_
            u_i =  u(t(i)); % u_
            dxdT_i = reshape(evaluate_state_sensitivity(sol,t(i)), nx,nT); % xT_ -> x_T
            dudT_i = reshape(evaluate_input_sensitivity(t(i)), nu,nT); % uT_ -> u_T
            % This does not need to be normalized because the components already are
            dydT = dydx(t(i), x_i, u_i) * dxdT_i + dydu(t(i), x_i, u_i) * dudT_i + dydk(t(i), x_i, u_i) * dkdT_maybe_normalized; % y_x * x_T + y_u * u_T * y_k * k_T -> y_T
            val(:,i) = vec(dydT); % y_T -> yT_
        end
    end

    function val = evaluate_state_curvature(sol, t)
        val = devals(sol, t, d2xdT2Start:d2xdT2End);
        if normalized
            dxdT = devals(sol, t, dxdTStart:dxdTEnd);
            [unused,val] = normalizeDerivatives(T, dxdT, val);
        end
    end

    function val = evaluate_input_curvature(t)
        nt = numel(t);
        
        val = zeros(nu*nT*nT,nt);
        for i = 1:nt
            d2udq2_i = d2udq2(t(i)); % uq_q
            d2udq2_i = d2udq2_i(uqUseInputControls,opts.UseInputControls); % uQ_Q
            d2udT2_i = [sparse(nu*(nTk+nTs),nT);
                        sparse(nu*nTq,nTk+nTs), d2udq2_i, sparse(nu*nTq,nTh);
                        sparse(nu*nTh,nT)]; % uT_T
            d2udT2_i = reshape(d2udT2_i, nu,nT*nT); % uT_T -> u_TT
            val(:,i) = vec(d2udT2_i);
        end
        
        if normalized
            dudT = evaluate_input_sensitivity_nonnormalized(t);
            [unused,val] = normalizeDerivatives(T, dudT, val);
        end
    end

    function val = evaluate_output_curvature(sol, t)
        nt = numel(t);
        
        val = zeros(ny*nT*nT,nt);
        for i = 1:nt
            x_i = deval(sol, t(i), 1:nx); % x_
            u_i =  u(t(i)); % u_
            dydx_i = dydx(t(i), x_i, u_i); % y_x
            dydu_i = dydu(t(i), x_i, u_i); % y_u
            dydk_i = dydk(t(i), x_i, u_i); % y_k
            dxdT_i = reshape(evaluate_state_sensitivity(sol, t(i)), nx,nT); % xT_ -> x_T
            dudT_i = reshape(evaluate_input_sensitivity(t(i)), nu,nT); % uT_ -> u_T
            d2xdT2_i = reshape(evaluate_state_curvature(sol, t(i)), nx,nT*nT); % xT_T -> x_TT
            d2udT2_i = reshape(evaluate_input_curvature(t(i)), nu,nT*nT);
            d2ydx2_i = d2ydx2(t(i), x_i, u_i); % yx_x
            d2ydu2_i = d2ydu2(t(i), x_i, u_i); % yx_x
            d2ydudx_i = d2ydudx(t(i), x_i, u_i); % yx_u
            d2ydk2_i = d2ydk2(t(i), x_i, u_i); % yk_k
            d2ydkdx_i = d2ydkdx(t(i), x_i, u_i); % yx_k
            d2ydkdu_i = d2ydkdu(t(i), x_i, u_i); % yu_k
            temp1 = d2ydx2_i * dxdT_i; % yx_x * x_T -> yx_T
            temp1 = reshape(spermute132(temp1, [ny,nx,nT], [ny*nT,nx]) * dxdT_i, ny,nT*nT); % (yx_T -> yT_x) * x_T -> yT_T -> y_TT
            temp2 = d2ydu2_i * dudT_i; % yu_u * u_T -> yu_T
            temp2 = reshape(spermute132(temp2, [ny,nu,nT], [ny*nT,nu]) * dudT_i, ny,nT*nT); % (yu_T -> yT_u) * u_T -> yT_T -> y_TT
            temp3 = d2ydk2_i * dkdT_maybe_normalized; % yk_k * k_T -> yk_T
            temp3 = reshape(spermute132(temp3, [ny,nk,nT], [ny*nT,nk]) * dkdT_maybe_normalized, ny,nT*nT); % (yk_T -> yT_k) * k_T -> yT_T -> y_TT
            temp4 = d2ydudx_i * dudT_i; % yx_u * u_T -> yx_T
            temp4 = spermute132(temp4, [ny,nx,nT], [ny*nT,nx]) * dxdT_i; % (yx_T -> yT_x) * x_T -> yT_T
            temp4 = reshape(temp4 + spermute132(temp4, [ny,nT,nT], [ny*nT,nT]), ny,nT*nT); % yT_T + (yT_T -> yT_T) -> yT_T -> y_TT
            temp5 = d2ydkdx_i * dkdT_maybe_normalized; % yx_k * k_T -> yx_T
            temp5 = spermute132(temp5, [ny,nx,nT], [ny*nT,nx]) * dxdT_i; % (yx_T -> yT_x) * x_T -> yT_T
            temp5 = reshape(temp5 + spermute132(temp5, [ny,nT,nT], [ny*nT,nT]), ny,nT*nT); % yT_T + (yT_T -> yT_T) -> yT_T -> y_TT
            temp6 = d2ydkdu_i * dkdT_maybe_normalized; % yu_k * k_T -> yu_T
            temp6 = spermute132(temp6, [ny,nu,nT], [ny*nT,nu]) * dudT_i; % (yu_T -> yT_u) * u_T -> yT_T
            temp6 = reshape(temp6 + spermute132(temp6, [ny,nT,nT], [ny*nT,nT]), ny,nT*nT); % yT_T + (yT_T -> yT_T) -> yT_T -> y_TT
            
            % Note d2kdT2 is zero, so dydk_i * d2kdT2 term is zero...
            if opts.Normalized
                % ...UNLESS normalizing, in which case there is a first
                % derivative contribution, which is nonzero
                Ti_is_Tj = find(speye(nT));
                d2kdT2 = sparse(repmat((1:nk).', nT, 1), vec(repmat(row(Ti_is_Tj), nk, 1)), dkdT_maybe_normalized(:), nk, nT*nT);
            else
                d2kdT2 = sparse(nk, nT*nT);
            end
            % Also, this doesn't have to be normalized either
            d2ydT2 = dydx_i * d2xdT2_i + dydu_i * d2udT2_i + dydk_i * d2kdT2 + temp1 + temp2 + temp3 + temp4 + temp5 + temp6;
            val(:,i) = vec(d2ydT2);
        end
    end
end
