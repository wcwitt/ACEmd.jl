"""
    ace_energy(potential, atoms, Kwargs)

Calculates ACE potential energy for atomic system.
The `atoms` object needs to be in `AtomsBase` compatable format.
The returned energy has a unit as defined by `Unitful`.

Parallel execution is done with Transducers.jl and there is an option to
use different executors. Look for `ThreadedEx` or other executors for more details on how to control it. 

# Kwargs
- `domain=1:length(atoms)`  :  choose subset of atoms to which energy is calculated
- `executor=ThreadedEx()`   :  used to control multithreading using Transducers.jl
- `energy_unit`  :   used to override energy unit for the calculation
- `length_unit`  :   used to override lenght unit for the calculation
- `cutoff_unit`  :   used to override unit that cutoff radius is defined
"""
function ace_energy(calc, at; domain=1:length(at), executor=ThreadedEx(), energy_unit=default_energy, kwargs...)
    nlist = neighborlist(at, get_cutoff(calc); storelist=false)
    Etot = Folds.sum( domain, executor ) do i
        _, R, Z = neigsz(nlist, at, i)
        ace_evaluate(calc, R, Z, _atomic_number(at,i))
    end
    return Etot * energy_unit
end

function ace_energy(V::ACE1.OneBody, at::ACE1.Atoms; domain=1:length(at), energy_unit=default_energy, kwargs...)
    E = sum( domain ) do i
        ACE1.evaluate(V, ACE1.chemical_symbol(at.Z[i]) )
    end
    return E * energy_unit
end

function ace_energy(V::ACE1.OneBody, as::AbstractSystem; domain=1:length(as), energy_unit=default_energy, kwargs...)
    E = sum( domain ) do i
        ACE1.evaluate(V, atomic_symbol(as, i) )
    end
    return E * energy_unit
end

# Generate interface for array potentials
for ace_method in [ :ace_energy, :ace_forces, :ace_virial, :ace_atom_energies ]
    @eval begin
        function $ace_method(calc::AbstractArray, at;
                domain=1:length(at),
                executor=ThreadedEx(),
                ntasks=Threads.nthreads(),
                energy_unit=default_energy,
                length_unit=default_length,
                cutoff_unit=default_length,
                kwargs...
            )
            tmp = map( calc ) do V
                Threads.@spawn $ace_method(V, at;
                    domain=domain,
                    executor=executor,
                    ntasks=ntasks,
                    energy_unit=energy_unit,
                    length_unit=length_unit,
                    cutoff_unit=cutoff_unit,
                    kwargs...
                )
            end
            return sum(fetch, tmp)
        end
    end
end

# Generate interface for ACEpotential type
for ace_method in [ :ace_energy, :ace_forces, :ace_virial, :ace_atom_energies ]
    @eval begin
        function $ace_method(calc::ACEpotential, at;
                domain=1:length(at),
                executor=ThreadedEx(),
                ntasks=Threads.nthreads(),
                energy_unit=calc.energy_unit,
                length_unit=calc.length_unit,
                cutoff_unit=calc.cutoff_unit,
                kwargs...
        )
            tmp = asyncmap( calc ) do V
                $ace_method(V, at;
                    domain=domain,
                    executor=executor,
                    ntasks=ntasks,
                    energy_unit=energy_unit,
                    length_unit=length_unit,
                    cutoff_unit=cutoff_unit,
                    kwargs...
                )
            end
            return sum( tmp )
        end
    end
end




## forces

"""
    ace_forces(potential, atoms, Kwargs)

Calculates forces for ACE potential for given atomic system.
The `atoms` object needs to be in `AtomsBase` compatable format.
The returned energy has a unit as defined by `Unitful`.

Parallel execution is done with Transducers.jl and there is an option to
use different executors. Look for `ThreadedEx` or other executors for more details on how to control it.
`ntasks` parameter is used to define number of task that the calculation is divided into. 

# Kwargs
- `domain=1:length(atoms)`          :  choose subset of atoms to which energy is calculated
- `executor=ThreadedEx()`           :  used to control multithreading using Transducers.jl
- `ntasks=Threads.nthreads()`       :  how many tasks are used in the calculation
- `energy_unit`  :   used to override energy unit for the calculation
- `length_unit`  :   used to override lenght unit for the calculation
- `cutoff_unit`  :   used to override unit that cutoff radius is defined
"""
function ace_forces(
    V,
    at;
    domain=1:length(at),
    executor=ThreadedEx(),
    ntasks=Threads.nthreads(),
    energy_unit=default_energy,
    length_unit=default_length,
    cutoff_unit=default_length,
    kwargs...
)   
    nlist = neighborlist(at, get_cutoff(V; cutoff_unit=cutoff_unit) )
    F = Folds.sum( collect(chunks(domain, ntasks)), executor ) do (d, _)
        ace_forces(V, at, nlist; domain=d)
    end
    return F * (energy_unit / length_unit)
end


function ace_forces(
    V, at, nlist;
    domain=1:length(at),
    kwargs...
)   
    f = zeros(SVector{3, Float64}, length(at))
    for i in domain
        j, R, Z = neigsz(nlist, at, i)
        _, tmp = ace_evaluate_d(V, R, Z, _atomic_number(at,i))

        for k in eachindex(j)
            f[j[k]] -= tmp.dV[k]
        end
        f[i] += sum(tmp.dV)
    end
    return f
end


function ace_forces(::ACE1.OneBody, at::ACE1.Atoms; energy_unit=default_energy, length_unit=default_length, kwargs...)
    T = (eltype ∘ eltype)(at.X)
    F = [ SVector{3}( zeros(T, 3) ) * (energy_unit / length_unit) for _ in 1:length(at) ]
    return F
end

function ace_forces(::ACE1.OneBody, as::AbstractSystem; energy_unit=default_energy, length_unit=default_length, kwargs...)
    T = eltype( ustrip.( position(as, 1) )  )
    F = [ SVector{3}( zeros(T, 3) ) * (energy_unit / length_unit) for _ in 1:length(as) ]
    return F
end


## virial

"""
    ace_virial(potential, atoms, Kwargs)

Calculates virial for ACE potential for given atomic system.
The `atoms` object needs to be in `AtomsBase` compatable format.
The returned energy has a unit as defined by `Unitful`.

Parallel execution is done with Transducers.jl and there is an option to
use different executors. Look for `ThreadedEx` for more details on how to control it. 

# Kwargs
- `domain=1:length(atoms)`  :  choose subset of atoms to which energy is calculated
- `executor=ThreadedEx()`   :  used to control multithreading using Transducers.jl
- `energy_unit`  :   used to override energy unit for the calculation
- `length_unit`  :   used to override lenght unit for the calculation
- `cutoff_unit`  :   used to override unit that cutoff radius is defined
"""
function ace_virial(V, at;
        domain=1:length(at),
        executor=ThreadedEx(),
        energy_unit=default_energy,
        length_unit=default_length,
        cutoff_unit=default_length,
        kwargs...
    )
    nlist = neighborlist(at, get_cutoff(V; cutoff_unit=cutoff_unit) )
    vir = Folds.sum( domain, executor ) do i
        j, R, Z = neigsz(nlist, at, i)
        _, tmp = ace_evaluate_d(V, R, Z, _atomic_number(at,i))
        site_virial = -sum( zip(R, tmp.dV) ) do (Rⱼ, dVⱼ)
            dVⱼ * Rⱼ'
        end
        site_virial
    end
    return vir * (energy_unit * length_unit)
end

function ace_virial(::ACE1.OneBody, at::ACE1.Atoms; energy_unit=default_energy, length_unit=default_length, kwargs...)
    T = (eltype ∘ eltype)(at.X)
    return SMatrix{3,3}(zeros(T, 3,3)) * (energy_unit * length_unit)
end

function ace_virial(::ACE1.OneBody, as::AbstractSystem; energy_unit=default_energy, length_unit=default_length, kwargs...)
    T = eltype( ustrip.( position( as[begin] ) )  )
    return SMatrix{3,3}(zeros(T, 3,3)) * (energy_unit * length_unit)
end


## Combinations
# these will be optimized later

function ace_energy_forces(pot, data; kwargs...)
    E = ace_energy(pot, data; kwargs...)
    F = ace_forces(pot, data; kwargs...)
    return Dict("energy"=>E, "forces"=>F)
end


function ace_energy_forces_virial(pot, data; kwargs...)
    E = ace_energy(pot, data; kwargs...)
    F = ace_forces(pot, data; kwargs...)
    V = ace_virial(pot, data; kwargs...)
    return Dict("energy"=>E, "forces"=>F, "virial"=>V)
end

function ace_forces_virial(pot, data; kwargs...)
    F = ace_forces(pot, data; kwargs...)
    V = ace_virial(pot, data; kwargs...)
    return Dict("forces"=>F, "virial"=>V)
end


## Individual atom energies

"""
    ace_atom_energies(potential, atoms; kwargs)

Calculates ACE potential energy for each atom.
The `atoms` object needs to be in `AtomsBase` compatable format.
The returned energy has a unit as defined by `Unitful`.

Parallel execution is done with Transducers.jl and there is an option to
use different executors. Look for `ThreadedEx` or other executors for more details on how to control it. 

# Kwargs
- `domain=1:length(atoms)`  :  choose subset of atoms to which energy is calculated
- `executor=ThreadedEx()`   :  used to control multithreading using Transducers.jl
- `energy_unit`  :   used to override energy unit for the calculation
- `length_unit`  :   used to override lenght unit for the calculation
- `cutoff_unit`  :   used to override unit that cutoff radius is defined
"""
function ace_atom_energies(calc, at; domain=1:length(at), executor=ThreadedEx(), energy_unit=default_energy, kwargs...)
    nlist = neighborlist(at, get_cutoff(calc); storelist=false)
    Etot = Folds.map( domain, executor ) do i
        _, R, Z = neigsz(nlist, at, i)
        ace_evaluate(calc, R, Z, _atomic_number(at,i))
    end
    return Etot * energy_unit
end

function ace_atom_energies(V::ACE1.OneBody, at::ACE1.Atoms; domain=1:length(at), energy_unit=default_energy, kwargs...)
    E = map( domain ) do i
        ACE1.evaluate(V, ACE1.chemical_symbol(at.Z[i]) )
    end
    return E * energy_unit
end

function ace_atom_energies(V::ACE1.OneBody, as::AbstractSystem; domain=1:length(as), energy_unit=default_energy, kwargs...)
    E = map( domain ) do i
        ACE1.evaluate(V, atomic_symbol(as, i) )
    end
    return E * energy_unit
end
