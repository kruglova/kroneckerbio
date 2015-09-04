function m = sbml2analytic(sbml)

m = InitializeModelAnalytic(sbml.name);

%% Clean up model
% TODO: ensure that compartment, parameters, etc have unique names
v_ids = vec({sbml.compartment.id});
for iv = 1:numel(sbml.compartment)
    vi = sbml.compartment(iv);
    if isempty(vi.name)
        sbml.compartment(iv).name = vi.id;
    end
end

for ik = 1:numel(sbml.parameter)
    ki = sbml.parameter(ik);
    if isempty(ki.name)
        sbml.parameter(ik).name = ki.id;
    end
end

for ixu = 1:numel(sbml.species)
    xui = sbml.species(ixu);
    if isempty(xui.name)
        sbml.species(ixu).name = xui.id;
    end
end

% Check for non-unique species names
nxu = numel(sbml.species);
xu_ids = vec({sbml.species.id});
xu_names = vec({sbml.species.name});
non_unique_species = false(nxu,1);
for ixu = 1:nxu
    non_unique_species(ixu) = ismember(xu_names{ixu}, xu_names([1:ixu-1, ixu+1:end]));
end

for ixu = row(find(non_unique_species))
    vx_i = lookup(sbml.species(ixu).compartment, v_ids);
    name = [sbml.compartment(vx_i).name, '_', sbml.species(ixu).name];
    proposal = name;
    index = 1;
    while ismember(proposal, {sbml.species.name})
        proposal = [name, '_', num2str(index)];
        index = index + 1;
    end
    sbml.species(ixu).name = proposal;
end

for ir = 1:numel(sbml.reaction)
    ri = sbml.reaction(ir);
    % Reactions are allowed to have empty names
    
    for ik = 1:numel(ri.kineticLaw.parameter)
        ki = ri.kineticLaw.parameter(ik);
        if isempty(ki.name)
            sbml.reaction(ir).kineticLaw.parameter(ik).name = ki.id;
        end
    end
end

% Copy stand-alone initial conditions to states
if isfield(sbml, 'initialAssignment')
    for ii = 1:numel(sbml.initialAssignment)
        i_i = sbml.initialAssignment(ii);
        i_state = lookup(i_i.symbol, xu_ids);
        
        assert(i_state ~= 0, 'KroneckerBio:SBML:UnsupportedInitialAssignment', 'Only species can be targets of initial assignment rules')
        
        sbml.species(i_state).isSetInitialAmount = true;
        sbml.species(i_state).initialAmount = i_i.math;
    end
end

z_handled = false(numel(sbml.rule),1); % Stores the rules need to be deleted
for iz = 1:numel(sbml.rule)
    zi = sbml.rule(iz);
    type = zi.typecode;
    name = zi.name;
    metaid = zi.metaid;
    target = zi.variable;
    formula = zi.formula;
    
    if strcmp(type, 'SBML_ASSIGNMENT_RULE')
        % Normal rule
    elseif strcmp(type, 'SBML_INITIAL_RULE')
        % Copy to state initial condition
        i_state = lookup(target, xu_ids);
        
        assert(i_state ~= 0, 'KroneckerBio:SBML:UnsupportedInitialAssignment', 'Only species can be targets of initial assignment rules')
        
        sbml.species(i_state).isSetInitialAmount = true;
        sbml.species(i_state).initialAmount = formula;
        
        z_handled(iz) = true;
    elseif strcmp(type, 'SBML_RATE_RULE')
        % Append as a reaction with a single product
        product = struct;
        product.species = target;
        product.stoichiometry = 1;
        
        kinetic_law = struct;
        kinetic_law.formula = formula;

        rate = struct;
        rate.metaid = metaid;
        rate.name = name;
        rate.product = product;
        rate.kineticLaw = kinetic_law;
        
        sbml.reaction = insertstruct(sbml.reaction, rate, numel(sbml.reaction)+1,1);

        z_handled(iz) = true;
    else
        error('KroneckerBio:SBML:UnsupportedRuleType', 'Unsupported rule type %s', type)
    end
end

sbml.rule(z_handled) = [];

%% Extract model
for iv = 1:numel(sbml.compartment)
    vi = sbml.compartment(iv);
    name = vi.name;
    id = vi.id;
    dim = vi.spatialDimensions;
    if vi.isSetSize
        size = vi.size;
    else
        % Had better be set by a rule
        size = NaN;
    end
    
    m = AddCompartment(m, name, dim, size, id);
end

for ik = 1:numel(sbml.parameter)
    ki = sbml.parameter(ik);
    name = ki.name;
    id = ki.id;
    value = ki.value;
    
    m = AddParameter(m, name, value, id);
end

for ixu = 1:nxu
    xi = sbml.species(ixu);
    name = xi.name;
    id = xi.id;
    compartment_index = lookup(xi.compartment, v_ids);
    compartment = sbml.compartment(compartment_index).name;
    is_input = xi.boundaryCondition || xi.constant;
    
    if xi.isSetInitialAmount
        value = xi.initialAmount;
    elseif xi.isSetInitialConcentration
        % TODO: determine if this is supposed to happen before or after initial assignments of compartment size
        value = xi.initialConcentration / sbml.compartment(compartment_index).size;
    else
        % Had better be set by a rule
        value = NaN;
    end
    
    if is_input
        m = AddInput(m, name, compartment, value, id);
    else
        m = AddState(m, name, compartment, value, id);
    end
end

xu_names = vec({sbml.species.name});
xu_ids = vec({sbml.species.id});
for ir = 1:numel(sbml.reaction)
    ri = sbml.reaction(ir);
    name = ri.name;
    id = ri.id;
    
    reactants = expand_reactants(ri.reactant, xu_names, xu_ids);
    products = expand_reactants(ri.product, xu_names, xu_ids);
    
    formula = ri.kineticLaw.formula;
    
    % Add parameters confined to reaction
    for ik = 1:numel(ri.kineticLaw.parameter)
        ki = ri.kineticLaw.parameter(ik);
        name_ik = ki.name;
        id = ki.id;
        value = ki.value;
        
        m = AddParameter(m, name_ik, value, id);
    end
    
    m = AddReaction(m, name, reactants, products, formula, [], id);
end

for iz = 1:numel(sbml.rule)
    % Only repeated assignment rules are left
    
    zi = sbml.rule(iz);
    target = zi.variable;
    formula = zi.formula;
    
    % See if it is a compartment size
    compartment_index = lookup(target, v_ids);
    if compartment_index ~= 0
        sbml.add.Compartments(compartment_index).Size = formula;
        continue
    end
    
    % See if it is a parameter value
    k_names = vec({m.add.Parameters(1:m.add.nk).Name});
    k_ids = vec({m.add.Parameters(1:m.add.nk).ID});
    parameter_index = lookup(target, k_ids);
    if parameter_index ~= 0
        % Extract parameter
        name = k_names{parameter_index};
        id = k_ids{parameter_index};
        
        % Remove parameter
        m = RemoveParameter(m, name);
        
        m = AddRule(m, name, formula, id);
        continue
    end
    
    % See if it is a species value
    xu_names = vec({m.add.Inputs(1:m.add.nu).Name, m.add.States(1:m.add.nx).Name});
    xu_ids = vec({m.add.Inputs(1:m.add.nu).ID, m.add.States(1:m.add.nx).ID});
    species_index = lookup(target, xu_ids);
    if species_index ~= 0
        % Extract species
        name = xu_names{species_index};
        id = xu_ids{species_index};
        
        % Remove species
        if species_index <= m.add.nu
            m = RemoveInput(m, name);
        else
            m = RemoveState(m, name);
        end
        
        m = AddRule(m, name, formula, id);
        continue
    end
end

assert(isempty(sbml.functionDefinition), 'KroneckerBio:SBML:functions', 'Model contains a function definition that is not surrently supported.')

end

function reactant_names = expand_reactants(reactants, xu_names, xu_ids)
n = numel(reactants);
reactant_names = cell(1,0);
for i = 1:n
    assert(isempty(reactants(i).stoichiometryMath), 'KroneckerBio:SBML:StoichiometryMath', 'Use of stiochiomerty math is not supported')

    id = reactants(i).species;
    name = xu_names{lookup(id, xu_ids)};
    stoich = reactants(i).stoichiometry;

    reactant_names = [reactant_names, repmat({name}, 1,stoich)];
end
end
