using IterTools
using LinearAlgebra
using Distributions

export master_operator, steady_state_masterOP, dynamics_masterOP


"""
	master_operator(p::Parameters, max_num; α=1.0)

	Calculates the master operator for the reaction network
	where the state space will be truncated at a maximum number 
	of species `max_num`
	
	Input
	p		Parameters struct for the reaction network
	max_num	number of species where the state space is truncated
	α		Plefka expansion parameter, default is α=1.0
	
	Returns the master operator and state space in a tuple
	
"""
function master_operator(p::Parameters, max_num::Int; α=1.0)
	
	num_species = length(p.k[1])	# number of species
	params = p.k	# reaction rates
	s_i = p.s_i		# Stoichiometric products
	r_i = p.r_i		# Stoichiometric reactants
	
	# state space
	x = [collect(0:max_num) for j in 1:num_species]
	state_space = reduce(vcat, collect(Iterators.product(x...)))
	
	# master operator
	master = zeros((max_num+1)^num_species, (max_num+1)^num_species)
	
	for s in state_space
	
		# get index from s (assume only one appearence)
		idx_s = findfirst(x->x==s, state_space)
		
		for j in 1:num_species
			
			# Annihiliation
			t = collect(s)
			t[j] += 1
			t = tuple(t...)
			if t[j] <= max_num
				idx_t = findfirst(x->x==t, state_space)		# index of t
				master[idx_s, idx_t] += params[2][j]*state_space[idx_t][j]
			end
			
			# Creation
			t = collect(s)
			t[j] -= 1
			t = tuple(t...)
			if t[j] >= 0
				idx_t = findfirst(x->x==t, state_space) 	# index of t
				master[idx_s, idx_t] += params[1][j]
			end
			
		end
			
		# Interaction
		for β in 1:length(params[3])
			
			new_state = tuple([(s[m] - s_i[β,m] + r_i[β,m]) for m in 1:num_species]...)
			
			if all(state_space[1] .<= new_state) && all(state_space[end] .>= new_state)
				idx = findfirst(x->x==new_state, state_space)
				r = α*params[3][β]
				for n in 1:num_species
					for p in 0:r_i[β,n]-1
						r *= (state_space[idx][n] - p)
					end
				end
				master[idx_s, idx] += r
			end
		
		end
	
	end
	
	# sum along columns must be zero
	master[diagind(master)] = -sum(master, dims=1)
	
	return (master, state_space)

end


"""
	steady_state_masterOP(master, state_space)
	
	Calculates the steady state of the master operator and state space
	
	Returns the steady state

"""
function steady_state_masterOP(master, state_space)

	num_species = length(state_space[1])	# number of species
	
	E = eigen(master, sortby=nothing)		# eigenvalues and eigenvectors
	
	# index of largest eigenvalue
	max_eig_idx = argmax(real.(E.values))
	
	# sum of eigenvectors of the highest eigenvalue
	sum_eigvecs = sum(abs.(E.vectors[:,max_eig_idx]))
	
	x0 = zeros(num_species)		# returned steady state
	
	for i in 1:length(state_space)
		for j in 1:num_species
			x0[j] += state_space[i][j] * abs(E.vectors[i,max_eig_idx]) / sum_eigvecs
		end
	end
	
	return x0

end


"""
	calc_mean_masterOP(p, state_space)
	
	Calculates the mean concentration with the probability vector `p`
	and state space
	
	Returns the calculated mean

"""
function calc_mean_masterOP(p::Vector{Float64}, state_space)

	num_species = length(state_space[1])	# number of species
	x = zeros(num_species)					# returned mean
	
	# sum of probabilities, should be == 1
	sum_p = sum(abs.(p))
	
	for i in 1:length(state_space)
		for j in 1:num_species
			x[j] += state_space[i][j] * abs(p[i]) / sum_p
		end
	end
	
	return x

end


"""
	initial_distr_state_space(state_space, x0)
	
	Calculates the initial Poisson distribution with means `x0` 
	for the different species.
	
	Returns the initial probability distribution vector

"""
function initial_distr_state_space(state_space, x0::Vector{Float64})

	num_species = length(state_space[1])	# number of species
	p0 = ones(length(state_space))			# initial prob. distr.
	
	for i in 1:length(state_space)
		for j in 1:num_species
			p0[i] *= pdf(Poisson(x0[j]), state_space[i][j])
		end
	end
	
	return p0

end


"""
	dynamics_masterOP(master, state_space, tspan, x0)
	
	Runs the dynamics for the master operator using an euler step integrator.
	
	Input
	master		master operator
	state_space	truncated state space
	tspan		time grid
	x0			initial condition for copy numbers	
	
	Returns is in a Result struct with time_grid and mean copy numbers

"""
function dynamics_masterOP(master, state_space, tspan::Vector{Float64}, x0::Vector{Float64})

	init_distr = initial_distr_state_space(state_space, x0)
	p = copy(init_distr)		# initial probability distribution
	
	dt = tspan[2] - tspan[1]	# delta_t time discretization
	num_species = length(state_space[1])	# number of species
	y = zeros(num_species, length(tspan))	# returned mean copy numbers
	y[:,1] = x0					# initial condition
	
	# run the dynamics
	for i in 1:length(tspan)-1
		p .+= dt .* (master * p)
		y[:,i+1] = calc_mean_masterOP(p, state_space)				
	end
	
	return Result(tspan, y)

end



