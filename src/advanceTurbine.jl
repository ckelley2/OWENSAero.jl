global dt = 0.0 #might not be used
global last_step1 = 0
global last_azi = 0.0
global last_stepL = 0
global last_stepU = 0
global timelast = 0
global z3D
global z3Dnorm
global us_param
global turbslices
global envslices
global CPL
global CPU
global RpL
global RpU
global TpL
global TpU
global ZpL
global ZpU
global XpL
global YpL
global XpU
global YpU
global alphaL
global alphaU
global clL
global clU
global cd_afL
global cd_afU
global VlocL
global VlocU
global ReL
global ReU
global thetavecL
global thetavecU
global deltaL
global deltaU
global Fx_baseL
global Fx_baseU
global Fy_baseL
global Fy_baseU
global Fz_baseL
global Fz_baseU
global Mx_baseL
global Mx_baseU
global My_baseL
global My_baseU
global Mz_baseL
global Mz_baseU
global power2L
global power2U
global powerL
global powerU
global delta = nothing
global aziL_save = nothing
global aziU_save = nothing
global startingtwist

"""
setupTurb(bld_x,bld_z,B,chord,TSR,Vinf;
    Height = maximum(bld_z),
    Radius = maximum(bld_x),
    eta = 0.25,
    twist = 0.0, #or array{Float,Nslices}
    rho = 1.225,
    mu = 1.7894e-5,
    RPI = true,
    tau = [0.3,3.0],
    ntheta = 30,
    Nslices = 30, #TODO: make this different from ntheta
    ifw = false,
    DSModel = "BV",
    AModel = "DMS",
    windangle_D = 0.0,
    afname = "(path)/airfoils/NACA_0015_RE3E5.dat", #TODO: analytical airfoil as default
    turbsim_filename = "(path)/data/ifw/turb_DLC1p3_13mps_330m_seed1.bts",
    ifw_libfile = joinpath(dirname(@__FILE__), "../bin/libifw_c_binding"))

Initializes aerodynamic models and sets up backend persistent memory to simplify intermittent calling within coupled solver loops

# Inputs
* `bld_x`: Blade x shape
* `bld_z`: Blade z shape
* `B`: Number of blades
* `chord`: chord length (m)
* `TSR`: Tip speed ratio
* `Vinf`: Inflow velocity
* `Height`:  turbine total height (m) typically maximum(bld_z) unless only the shape and not size of bld_z is being used
* `Radius`:  turbine nominal radius (m) typically maximum(bld_x) unless only shape and not size of bld_x is used
* `eta`: blade mount point ratio, i.e. 0.25 would be at the quarter chord
* `twist`: 0.0, #or array{Float,Nslices}
* `rho`: working fluid density (kg/m^3)
* `mu`:  working fluid density (standard SI units)
* `RPI`: RPI method flag
* `tau`: Unsteady wake propogation time constants [0.3,3.0],
* `ntheta`: Number of azimuthal discretizations
* `Nslices`: Number of vertical slices of the turbine
* `ifw`: flag for inflow wind
* `DSModel`:  Dynamic stall model "BV" or "none" or "LB" when we get it working
* `AModel`:  Aerodynamic model "DMS" or "AC"
* `windangle_D`:  Inflow wind angle (degrees)
* `afname`: airfoil path and name e.g. "(path)/airfoils/NACA_0015_RE3E5.dat"
* `turbsim_filename`: turbsim path and name e.g. "(path)/data/ifw/turb_DLC1p3_13mps_330m_seed1.bts",
* `ifw_libfile`:  inflow wind dynamic library location e.g. joinpath(dirname(@__FILE__), "../../../openfast/build/modules/inflowwind/libifw_c_binding"))


# Outputs:
* `none`:

"""
function setupTurb(bld_x,bld_z,B,chord,TSR,Vinf;
    Height = maximum(bld_z),
    Radius = maximum(bld_x),
    eta = 0.25,
    twist = 0.0,
    rho = 1.225,
    mu = 1.7894e-5,
    RPI = true,
    tau = [0.3,3.0],
    ntheta = 30,
    Nslices = 30, #TODO: make this different from ntheta
    ifw = false,
    DSModel = "BV",
    AModel = "DMS",
    windangle_D = 0.0,
    afname = "$(path)/airfoils/NACA_0015_RE3E5.dat", #TODO: analytical airfoil as default
    turbsim_filename = "$path/data/ifw/turb_DLC1p3_13mps_330m_seed1.bts",
    ifw_libfile = nothing)

    global dt = 0.0 #might not be used
    global last_step1 = 0
    global last_stepL = 0
    global last_stepU = 0
    global last_azi = 0.0
    global timelast = 0.0
    global delta = nothing
    global aziL_save = nothing
    global aziU_save = nothing

    if length(chord) == 1
        chord = chord.*ones(Real,Nslices)
    end

    if isa(afname, String) #This allows for either a single airfoil for all, or if it is an array of strings it won't enter here and they will be used
        afname = fill(afname,Nslices)
    end

    shapeX_spline = FLOWMath.Akima(bld_z, bld_x)

    shapeY = collect(LinRange(0,Height,Nslices+1))
    shapeX = shapeX_spline(shapeY)

    global z3D = (shapeY[2:end] + shapeY[1:end-1])/2.0 .+1.0 #TODO: ensure the turbsim can use the correct z value i.e. it is within its window
    global z3Dnorm = (z3D .- 1.0)./Height
    # RefArea_half, error = QuadGK.quadgk(shapeX_spline, 0, Height, atol=1e-10)
    # RefArea = RefArea_half*2
    RefArea = pi*Height/2*Radius #automatic gradients cant make it through quadgk
    delta_xs = shapeX[2:end] - shapeX[1:end-1]
    delta_zs = shapeY[2:end] - shapeY[1:end-1]

    delta3D = atan.(delta_xs./delta_zs)

    r3D = (shapeX[2:end,1]+shapeX[1:end-1,1])/2.0
    aerocenter_dist = (eta-.25).*chord[1]

    twist3D = -atan.(aerocenter_dist./r3D).+twist#ones(Nslices)*-0.4*pi/180
    global startingtwist = twist3D
    omega = ones(Real,ntheta) .* Vinf/Radius*TSR
    RPM = omega[1]/2/pi*60

    function affun(alpha, Re, M;V_twist=nothing,chord=nothing,dt=nothing,Vloc=nothing)

        cl = 6.2*alpha
        cd = 0.008 .- 0.003.*cl + 0.01.*cl.*cl

        return cl, cd
    end

    if ifw
        OWENSOpenFASTWrappers.ifwinit(;inflowlib_filename=ifw_libfile,turbsim_filename)
    end

    # TODO: clean this up
    V_xtemp = Vinf*ones(Real,ntheta)
    V_ytemp = zeros(Real,size(V_xtemp))
    V_z = zeros(Real,size(V_xtemp))
    V_twist = zeros(Real,size(V_xtemp))
    windangle = windangle_D * pi/180
    V_x = V_xtemp*cos(windangle)-V_ytemp*sin(windangle)
    V_y = V_xtemp*sin(windangle)+V_ytemp*cos(windangle)

    # Set up structs for the entire turbine
    global us_param = OWENSAero.UnsteadyParams(RPI,tau,ifw)
    global turbslices = Array{OWENSAero.Turbine}(undef,Nslices)
    global envslices = Array{OWENSAero.Environment}(undef,Nslices)

    for islice = 1:Nslices

        if DSModel=="BV"
            af = OWENSAero.readaerodyn_BV_NEW(afname[islice])
        elseif DSModel=="none" #Dyn stall is not gradient safe
            af = OWENSAero.readaerodyn_BV_NEW(afname[islice],DSModel="none")
        else
            af = affun
        end

        r = ones(Real,ntheta).*r3D[islice]
        twist = ones(Real,ntheta).*twist3D[islice]
        delta = ones(Real,ntheta).*delta3D[islice]
        turbslices[islice] = OWENSAero.Turbine(Radius,r,z3D[islice],chord[islice],twist,delta,omega,B,af,ntheta,false)
        envslices[islice] = OWENSAero.Environment(rho,mu,V_x,V_y,V_z,V_twist,windangle,DSModel,AModel,zeros(Real,ntheta*2))
    end
end


function deformTurb(azi;newOmega=-1,newVinf=-1,bld_x=-1,
bld_z=-1,
bld_twist=-1,
steady=false) # each of these is size ntheta x nslices


    global z3D
    # Interpolate to the vertical positions
    if bld_x!=-1 && bld_z!=-1 && bld_twist!=-1
        bld_x_temp = zeros(length(bld_x[:,1]),length(z3D))
        bld_twist_temp = zeros(length(bld_x[:,1]),length(z3D))
        for ibld = 1:length(bld_x[:,1])
            bld_x_temp[ibld,:] = FLOWMath.akima(bld_z[ibld,:],bld_x[ibld,:],z3D.-1.0) #TODO: get rid of this -1.0, which is from inflowwind not liking evaluation at the boundary
            bld_twist_temp[ibld,:] = FLOWMath.akima(bld_z[ibld,:],bld_twist[ibld,:],z3D.-1.0)
        end
        bld_x = bld_x_temp
        bld_twist = bld_twist_temp
        bld_z = zeros(Real,size(bld_x)) #TODO: a better way to do this.
        for ibld = 1:length(bld_x[:,1])
            bld_z[ibld,:] = z3D.-1.0
        end
    elseif (bld_x!=-1 && bld_z!=-1) && bld_twist==-1
        @warn "blade x, z, and twist deformations must be specified together"
    end

    global turbslices
    global envslices
    global last_step1
    global startingtwist
    ntheta = turbslices[1].ntheta
    # Get the last step's blade index.
    dtheta = 2*pi/ntheta
    if steady
        n_steps = 1
    else
        n_steps = max(1,round(Int,azi/dtheta) - last_step1)
    end
    last_azi = last_step1*dtheta
    if n_steps == 1
        azi_used = [azi]
    else
        azi_used = LinRange(last_azi,azi,n_steps)
    end

    for istep = 1:n_steps
        bld1_idx = round(Int,azi_used[istep]/dtheta)%ntheta #step1%ntheta
        if bld1_idx == 0
            bld1_idx = ntheta
        end
        dstep_bld = Int(turbslices[1].ntheta/turbslices[1].B)

        # Calculate new delta
        if bld_x != -1 && bld_z != -1
            delta3D = zeros(Real,turbslices[1].B,length(bld_x[1,:]))
            for ibld = 1:turbslices[1].B
                delta_xs = bld_x[ibld,2:end] - bld_x[ibld,1:end-1]
                delta_zs = bld_z[ibld,2:end] - bld_z[ibld,1:end-1]

                delta3D[ibld,1:end-1] = atan.(delta_xs./delta_zs)
                delta3D[ibld,end] = delta3D[ibld,end-1]
            end
        end

        # Apply the new values to the structs at each slice
        for islice = 1:length(turbslices)
            for ibld = 1:turbslices[1].B

                bld_idx = (bld1_idx+dstep_bld*(ibld-1))%(ntheta-1)
                if bld_idx == 0
                    bld_idx = 1
                end

                if bld_x!=-1 && bld_z!=-1 && bld_twist!=-1
                    turbslices[islice].r[bld_idx] = bld_x[ibld,islice]
                    # turbslices[islice].z[islice] = bld_z[ibld,islice]
                    # turbslices[islice].chord = chord[islice]
                    turbslices[islice].delta[bld_idx] = delta3D[ibld,islice]
                    turbslices[islice].twist[bld_idx] = startingtwist[islice]+bld_twist[ibld,islice]
                end

                if newOmega != -1
                    turbslices[islice].omega[bld_idx] = newOmega #Omega is the same for all blades and all slices at a given point in time
                end
                if newVinf !== -1
                    envslices[islice].V_x[bld_idx] = newVinf #TODO: map to turbulent inflow?
                end

                # #TODO: add motion related velocity without compounding erroneously, might use global variables to store last state
                # # envslices[ii].V_x = V_x
                # if Vinf!=0
                #     envslices[ii].V_x = Vinf
                # end
                # # envslices[ii].V_y = V_y
                # # envslices[ii].V_z = V_z
                # # envslices[ii].V_twist = V_twist
            end
        end
    end
end


"""
    advanceTurb(tnew;ts=2*pi/(turbslices[1].omega[1]*turbslices[1].ntheta))

Runs a previously initialized aero model (see ?setupTurb) in the unsteady mode (can be repeateadly called, or called for a specific time, or repeatedly called for sections of time)

# Inputs
* `tnew::float`: new time (s); will run from last time specified from the last call, to the current time specified, or from t=ts if the first time called
* `ts::float`: optional, desired timestep.  Will run at finer timesteps than the azimuthal discretization without interfering with wake propogation.  While possible, it is not recommended to run with timesteps larger than the azimuthal discretization (hence the optional nature and automatic calculation)

# Outputs:
* `CP`: Turbine coefficient of performance
* `Rp`: Array(B,Nslices,n_steps) of radial force (N) where n_steps = max(1,round(Int,(tnew-timelast)/ts))
* `Tp`: Array(B,Nslices,n_steps) of tangential force (N)
* `Zp`: Array(B,Nslices,n_steps) of vertical force (N)
* `alpha`: Array(B,Nslices,n_steps) of angle of attack (rad)
* `cl`: Array(B,Nslices,n_steps) of airfoil cl used
* `cd_af`: Array(B,Nslices,n_steps) of airfoil cd used
* `Vloc`: Array(B,Nslices,n_steps) of airfoil local velocity used
* `Re`: Array(B,Nslices,n_steps) of airfoil Reynolds number used
* `thetavec`: Azimuthal discretization location (rad)
* `ntheta`: number of azimuthal discretizations used
* `Fx_base`: Array(ntheta)Turbine base Fx (N)
* `Fy_base`: Array(ntheta)Turbine base Fy (N)
* `Fz_base`: Array(ntheta)Turbine base Fz (N)
* `Mx_base`: Array(ntheta)Turbine base Mx (N-m)
* `My_base`: Array(ntheta)Turbine base My (N-m)
* `Mz_base`: Array(ntheta)Turbine base Mz (N-m)
* `power`: Array(ntheta)Turbine power (watts)
* `power2`: Turbine average power for the revolution (watts)
* `torque`: Array(ntheta)Turbine torque (N-m) (alternative calculation method from Mz-base)

"""
function advanceTurb(tnew;ts=2*pi/(turbslices[1].omega[1]*turbslices[1].ntheta),azi=-1.0,verbosity=0,alwaysrecalc=nothing,last_step=nothing)
    global timelast
    global us_param
    global turbslices
    global envslices
    global dt = ts
    RPM = mean(turbslices[1].omega)/2/pi*60
    omega = turbslices[1].omega
    B = turbslices[1].B
    Nslices = length(turbslices)
    ntheta = turbslices[1].ntheta
    dtheta = 2*pi/(ntheta)

    global last_step1 # = round(Int,timelast*RPM/60*ntheta)
    if last_step!=nothing
        last_step1 = last_step
    end
    global last_azi
    if azi == -1.0
        n_steps = max(1,round(Int,(tnew-timelast)/ts))
        ts_base = 2*pi/(omega[1]*ntheta)
        azi = last_azi + n_steps * dtheta * ts/ts_base
    else
        n_steps = max(1,round(Int,azi/dtheta) - last_step1)
    end

    CP = zeros(Nslices,n_steps)
    Rp = zeros(B,Nslices,n_steps)
    Tp = zeros(B,Nslices,n_steps)
    Zp = zeros(B,Nslices,n_steps)
    Xp = zeros(B,Nslices,n_steps)
    Yp = zeros(B,Nslices,n_steps)
    Vloc = zeros(B,Nslices,n_steps)
    alpha = zeros(B,Nslices,n_steps)
    delta = zeros(B,Nslices)
    cl = zeros(Nslices,n_steps)
    cd_af = zeros(Nslices,n_steps)
    Re = zeros(Nslices,n_steps)
    # thetavec = zeros(Nslices,n_steps)
    thetavec = zeros(B,n_steps)

    # Base Loads
    Fx_base = zeros(n_steps)
    Fy_base = zeros(n_steps)
    Fz_base = zeros(n_steps)
    Mx_base = zeros(n_steps)
    My_base = zeros(n_steps)
    Mz_base = zeros(n_steps)
    power = zeros(n_steps)
    power2 = zeros(n_steps)

    rev_step = 0
    step1 = 0 #initialize scope
    for istep = 1:n_steps#(itime,time) in enumerate(timevec)

        if verbosity>0
            println("istep $istep of $(n_steps)")
        end

        step1 = last_step1+istep #if this is an iterated solve, last_step1 won't get updated until a new time is specified

        step_idx = max(1,step1-last_step1) #Single time step handling
        if step_idx>n_steps
            step_idx = n_steps
        end

        Fx = zeros(Nslices)
        Fy = zeros(Nslices)
        Fz = zeros(Nslices)
        Mx = zeros(Nslices)
        My = zeros(Nslices)
        Mz = zeros(Nslices)
        integralpower = zeros(Nslices)

        bnum = 1
        rev_step = Int(step1-floor(Int,(step1-1)/ntheta)*ntheta + (bnum-1)*ntheta/B)
        if rev_step>ntheta
            rev_step -= ntheta
        end

        for islice = 1:Nslices

            CP_temp, Th_temp, Q_temp, Rp_temp, Tp_temp, Zp_temp, Vloc_temp,
            CD_temp, CT_temp, a_temp, awstar_temp, alpha_temp, cl_temp, cd_temp,
            thetavec_temp, Re_temp = OWENSAero.Unsteady_Step(turbslices[islice],envslices[islice],us_param,step1)

            # Intermediate base loads
            r = turbslices[islice].r
            for iblade = 1:B
                bld_idx = Int(step1-floor(Int,(step1-1)/ntheta)*ntheta + (iblade-1)*ntheta/B)
                if bld_idx>ntheta
                    bld_idx = Int(bld_idx-ntheta)
                end

                Fx[islice] += Rp_temp[bld_idx].*sin.(thetavec_temp[bld_idx]) - Tp_temp[bld_idx].*cos.(thetavec_temp[bld_idx])
                Fy[islice] += -Rp_temp[bld_idx].*cos.(thetavec_temp[bld_idx]) - Tp_temp[bld_idx].*sin.(thetavec_temp[bld_idx])
                Fz[islice] += Zp_temp[bld_idx]
                Mx[islice] += Zp_temp[bld_idx].*r[bld_idx].*cos.(thetavec_temp[bld_idx])
                My[islice] += Zp_temp[bld_idx].*r[bld_idx].*sin.(thetavec_temp[bld_idx])
                Mz[islice] += Tp_temp[bld_idx].*r[bld_idx]

                Rp[iblade,islice,step_idx] = Rp_temp[bld_idx]
                Tp[iblade,islice,step_idx] = Tp_temp[bld_idx]
                Xp[iblade,islice,step_idx] = Rp_temp[bld_idx].*sin.(thetavec_temp[bld_idx]) - Tp_temp[bld_idx].*cos.(thetavec_temp[bld_idx])
                Yp[iblade,islice,step_idx] = -Rp_temp[bld_idx].*cos.(thetavec_temp[bld_idx]) - Tp_temp[bld_idx].*sin.(thetavec_temp[bld_idx])
                Zp[iblade,islice,step_idx] = Zp_temp[bld_idx]
                Vloc[iblade,islice,step_idx] = Vloc_temp[bld_idx]
                alpha[iblade,islice,step_idx] = alpha_temp[bld_idx]

                thetavec[iblade,istep] = thetavec_temp[bld_idx]+ntheta*dtheta*floor(Int,(step1-1)/ntheta) # thetavec[blade index] * revolution
                delta[iblade,islice] = turbslices[islice].delta[bld_idx]
            end
            integralpower[islice] = B/(2*pi)*OWENSAero.pInt(thetavec_temp, Tp_temp.*r.*omega)

            cl[islice,step_idx] = cl_temp[rev_step]
            cd_af[islice,step_idx] = cd_temp[rev_step]
            Re[islice,step_idx] = Re_temp[rev_step]

        end

        global z3D
        global z3Dnorm

        # Base loads
        Fx_base[step_idx] = OWENSAero.trapz(z3D,Fx)
        Fy_base[step_idx] = OWENSAero.trapz(z3D,Fy)
        Fz_base[step_idx] = OWENSAero.trapz(z3D,Fz)

        Mx_base[step_idx] = OWENSAero.trapz(z3D,(-Fy.*z3D)+Mx)
        My_base[step_idx] = OWENSAero.trapz(z3D,(Fx.*z3D)+My)
        Mz_base[step_idx] = OWENSAero.trapz(z3D,Mz)

        power[step_idx] = OWENSAero.trapz(z3D,integralpower)
        power2[step_idx] = Mz_base[step_idx]*mean(abs.(omega))

    end

    if (azi-last_azi) >= dtheta*(1-1e-6)
        last_step1 = step1
        last_azi = azi
    end

    if timelast != tnew
        timelast = tnew
    end

    return CP,Rp,Tp,Zp,alpha,cl,cd_af,Vloc,Re,thetavec,n_steps,Fx_base,Fy_base,Fz_base,Mx_base,My_base,Mz_base,power,power2,rev_step,z3Dnorm,delta,Xp,Yp,step1
end


"""
    steadyTurb(omega,Vinf)

Runs a previously initialized aero model (see ?setupTurb) in the steady state mode

# Inputs
* `omega::float`: turbine rotation rate (rad/s)
* `Vinf::float`: turbine steady inflow velocity (m/s)


# Outputs:
* `CP`: Turbine coefficient of performance
* `Rp`: Array(B,Nslices,ntheta) of radial force (N)
* `Tp`: Array(B,Nslices,ntheta) of tangential force (N)
* `Zp`: Array(B,Nslices,ntheta) of vertical force (N)
* `alpha`: Array(B,Nslices,ntheta) of angle of attack (rad)
* `cl`: Array(B,Nslices,ntheta) of airfoil cl used
* `cd_af`: Array(B,Nslices,ntheta) of airfoil cd used
* `Vloc`: Array(B,Nslices,ntheta) of airfoil local velocity used
* `Re`: Array(B,Nslices,ntheta) of airfoil Reynolds number used
* `thetavec`: Azimuthal discretization location (rad)
* `ntheta`: number of azimuthal discretizations used
* `Fx_base`: Array(ntheta)Turbine base Fx (N)
* `Fy_base`: Array(ntheta)Turbine base Fy (N)
* `Fz_base`: Array(ntheta)Turbine base Fz (N)
* `Mx_base`: Array(ntheta)Turbine base Mx (N-m)
* `My_base`: Array(ntheta)Turbine base My (N-m)
* `Mz_base`: Array(ntheta)Turbine base Mz (N-m)
* `power`: Array(ntheta)Turbine power (watts)
* `power2`: Turbine average power for the revolution (watts)
* `torque`: Array(ntheta)Turbine torque (N-m) (alternative calculation method from Mz-base)

"""
function steadyTurb(;omega = -1,Vinf = -1)

    # global us_param #TODO: add turbulence lookup option for steady?
    global turbslices
    global envslices

    # RPM = omega/2/pi*60
    B = turbslices[1].B
    Nslices = length(turbslices)
    ntheta = turbslices[1].ntheta

    CP = zeros(Real,Nslices,ntheta)
    Rp = zeros(Real,B,Nslices,ntheta)
    Tp = zeros(Real,B,Nslices,ntheta)
    Zp = zeros(Real,B,Nslices,ntheta)
    alpha = zeros(Real,B,Nslices,ntheta)
    cl = zeros(Real,Nslices,ntheta)
    cd_af = zeros(Real,Nslices,ntheta)
    Vloc = zeros(Real,Nslices,ntheta)
    Re = zeros(Real,Nslices,ntheta)
    thetavec = zeros(Real,Nslices,ntheta)
    delta = zeros(Real,B,Nslices)

    Fx = zeros(Real,Nslices,ntheta)
    Fy = zeros(Real,Nslices,ntheta)
    Fz = zeros(Real,Nslices,ntheta)
    Mx = zeros(Real,Nslices,ntheta)
    My = zeros(Real,Nslices,ntheta)
    Mz = zeros(Real,Nslices,ntheta)
    Mz2 = zeros(Real,Nslices)
    integralpower = zeros(Real,Nslices)
    integraltorque = zeros(Real,Nslices)


    for islice = 1:Nslices

        if Vinf != -1
            envslices[islice].V_x[:] .= Vinf
        end
        # envslices[islice].V_y[:] .= 0.0
        # envslices[islice].V_z[:] .= 0.0
        if omega != -1
            turbslices[islice].omega .= omega
        end

        CP_temp, Th_temp, Q_temp, Rp_temp, Tp_temp, Zp_temp, Vloc[islice,:],
        CD_temp, CT_temp, a_temp, awstar_temp, alpha_temp, cl[islice,:], cd_af[islice,:],
        thetavec, Re[islice,:] = OWENSAero.steady(turbslices[islice],envslices[islice])

        # Intermediate base loads
        r = turbslices[islice].r
        for iblade = 1:B
            for step1 = 1:ntheta
                bld_idx = Int(step1-floor(Int,(step1-1)/ntheta)*ntheta + (iblade-1)*ntheta/B)
                if bld_idx>ntheta
                    bld_idx = Int(bld_idx-ntheta)
                end

                Fx[islice,step1] += -Rp_temp[bld_idx].*sin.(thetavec[bld_idx]) + Tp_temp[bld_idx].*cos.(thetavec[bld_idx])
                Fy[islice,step1] += Rp_temp[bld_idx].*cos.(thetavec[bld_idx]) + Tp_temp[bld_idx].*sin.(thetavec[bld_idx])
                Fz[islice,step1] += Zp_temp[bld_idx]
                Mx[islice,step1] += Zp_temp[bld_idx].*r[bld_idx].*cos.(thetavec[bld_idx])
                My[islice,step1] += Zp_temp[bld_idx].*r[bld_idx].*sin.(thetavec[bld_idx])
                Mz[islice,step1] += Tp_temp[bld_idx].*r[bld_idx]
                Mz2[islice] += Tp_temp[bld_idx].*r[bld_idx] .* 2*pi/ntheta

                Rp[iblade,islice,step1] = Rp_temp[bld_idx]
                Tp[iblade,islice,step1] = Tp_temp[bld_idx]
                Zp[iblade,islice,step1] = Zp_temp[bld_idx]
                alpha[iblade,islice,step1] = alpha_temp[bld_idx]
                delta[iblade,islice] = turbslices[islice].delta[bld_idx]
            end
        end
        integralpower[islice] = B/(2*pi)*OWENSAero.pInt(thetavec, Tp_temp.*r.*turbslices[islice].omega)
        integraltorque[islice] = B/(2*pi)*OWENSAero.pInt(thetavec, Tp_temp.*r)
    end

    global z3D

    Fx_base = zeros(Real,ntheta)
    Fy_base = zeros(Real,ntheta)
    Fz_base = zeros(Real,ntheta)
    Mx_base = zeros(Real,ntheta)
    My_base = zeros(Real,ntheta)
    Mz_base = zeros(Real,ntheta)
    Mz_base2 = OWENSAero.trapz(z3D,Mz2)

    for itheta = 1:ntheta
        # Base loads
        Fx_base[itheta] = OWENSAero.trapz(z3D,Fx[:,itheta])
        Fy_base[itheta] = OWENSAero.trapz(z3D,Fy[:,itheta])
        Fz_base[itheta] = OWENSAero.trapz(z3D,Fz[:,itheta])

        Mx_base[itheta] = OWENSAero.trapz(z3D,(Fy[:,itheta].*z3D)+Mx[:,itheta])
        My_base[itheta] = OWENSAero.trapz(z3D,(Fx[:,itheta].*z3D)+My[:,itheta])
        Mz_base[itheta] = OWENSAero.trapz(z3D,Mz[:,itheta])

    end

    power = OWENSAero.trapz(z3D,integralpower)
    torque = OWENSAero.trapz(z3D,integraltorque)
    power2 = mean(Mz_base)*mean(abs.(omega))

    global z3Dnorm
    return CP,Rp,Tp,Zp,alpha,cl,cd_af,Vloc,Re,thetavec,ntheta,Fx_base,Fy_base,Fz_base,Mx_base,My_base,Mz_base,power,power2,torque,z3Dnorm,delta,Mz_base2
end

function AdvanceTurbineInterpolate(t;azi=-1,alwaysrecalc=false)
    global last_stepL
    global last_stepU
    global CPL
    global CPU
    global RpL
    global RpU
    global TpL
    global TpU
    global ZpL
    global ZpU
    global XpL
    global YpL
    global XpU
    global YpU
    global alphaL
    global alphaU
    global clL
    global clU
    global cd_afL
    global cd_afU
    global VlocL
    global VlocU
    global ReL
    global ReU
    global thetavecL
    global thetavecU
    global deltaL
    global deltaU
    global Fx_baseL
    global Fx_baseU
    global Fy_baseL
    global Fy_baseU
    global Fz_baseL
    global Fz_baseU
    global Mx_baseL
    global Mx_baseU
    global My_baseL
    global My_baseU
    global Mz_baseL
    global Mz_baseU
    global power2L
    global power2U


    global powerL
    global powerU
    global z3Dnorm
    global delta
    global aziL_save
    global aziU_save
    global turbslices
    ntheta = turbslices[1].ntheta
    dtheta = 2*pi/ntheta

    # Get lower point
    aziL = floor(azi/dtheta)*dtheta #TODO: time only input
    if aziL_save != aziL || alwaysrecalc # do it on the first round or if it has changed
        if aziL == aziU_save && !alwaysrecalc # if the bottom is now what was the top, swap and don't recalculate
            aziL_save = aziU_save
             CPL[:,end] = CPU[:,end]
             RpL[:,:,end] = RpU[:,:,end]
             TpL[:,:,end] = TpU[:,:,end]
             ZpL[:,:,end] = ZpU[:,:,end]
             XpL[:,:,end] = XpU[:,:,end]
             YpL[:,:,end] = YpU[:,:,end]
             alphaL[:,:,end] = alphaU[:,:,end]
             clL[:,end] = clU[:,end]
             cd_afL[:,end] = cd_afU[:,end]
             VlocL[:,:,end] = VlocU[:,:,end]
             ReL[:,end] = ReU[:,end]
             thetavecL[:,end] = thetavecU[:,end]
             Fx_baseL[end] = Fx_baseU[end]
             Fy_baseL[end] = Fy_baseU[end]
             Fz_baseL[end] = Fz_baseU[end]
             Mx_baseL[end] = Mx_baseU[end]
             My_baseL[end] = My_baseU[end]
             Mz_baseL[end] = Mz_baseU[end]
             powerL[end] = powerU[end]
             power2L[end] = power2U[end]
        else

            CPL,RpL,TpL,ZpL,alphaL,clL,cd_afL,VlocL,ReL,thetavecL,ntheta,Fx_baseL,
            Fy_baseL,Fz_baseL,Mx_baseL,My_baseL,Mz_baseL,powerL,power2L,_,_,
            delta,XpL,YpL,last_step = advanceTurb(t;azi=aziL,last_step=last_stepL)
            if aziL_save != aziL
                last_stepL = last_step
            end
            aziL_save = aziL
        end
    end

    aziU = ceil(azi/dtheta)*dtheta

    if aziU==aziL && aziU_save != nothing && !alwaysrecalc
        CPU[:,end] = CPL[:,end]
        RpU[:,:,end] = RpL[:,:,end]
        TpU[:,:,end] = TpL[:,:,end]
        ZpU[:,:,end] = ZpL[:,:,end]
        XpU[:,:,end] = XpL[:,:,end]
        YpU[:,:,end] = YpL[:,:,end]
        alphaU[:,:,end] = alphaL[:,:,end]
        clU[:,end] = clL[:,end]
        cd_afU[:,end] = cd_afL[:,end]
        VlocU[:,:,end] = VlocL[:,:,end]
        ReU[:,end] = ReL[:,end]
        thetavecU[:,end] = thetavecL[:,end]
        Fx_baseU[end] = Fx_baseL[end]
        Fy_baseU[end] = Fy_baseL[end]
        Fz_baseU[end] = Fz_baseL[end]
        Mx_baseU[end] = Mx_baseL[end]
        My_baseU[end] = My_baseL[end]
        Mz_baseU[end] = Mz_baseL[end]
        powerU[end] = powerL[end]
        power2U[end] = power2L[end]
    else
        if aziU_save != aziU || alwaysrecalc # Do the same for the top

            CPU,RpU,TpU,ZpU,alphaU,clU,cd_afU,VlocU,ReU,thetavecU,ntheta,Fx_baseU,
            Fy_baseU,Fz_baseU,Mx_baseU,My_baseU,Mz_baseU,powerU,power2U,_,_,
            delta,XpU,YpU,last_step = advanceTurb(t;azi=aziU,last_step=last_stepU)
            if aziU_save != aziU
                last_stepU = last_step
            end
            aziU_save = aziU
        end
    end

    # Initialize the outputs, TODO: nonallocation
    NBlade = length(RpL[:,1,1])
    Nslices = length(RpL[1,:,1])

    n_steps = 1
    CP = zeros(Real,Nslices,n_steps)
    Rp = zeros(Real,NBlade,Nslices,n_steps)
    Tp = zeros(Real,NBlade,Nslices,n_steps)
    Zp = zeros(Real,NBlade,Nslices,n_steps)
    Xp = zeros(Real,NBlade,Nslices,n_steps)
    Yp = zeros(Real,NBlade,Nslices,n_steps)
    Vloc = zeros(Real,NBlade,Nslices,n_steps)
    alpha = zeros(Real,NBlade,Nslices,n_steps)
    cl = zeros(Real,Nslices,n_steps)
    cd_af = zeros(Real,Nslices,n_steps)
    Re = zeros(Real,Nslices,n_steps)
    thetavec = zeros(Real,NBlade,n_steps)

    # linearly interpolate
    if aziU!=aziL
        fraction = (azi - aziL)/(aziU - aziL) #TODO: only alwaysrecalc upper or lower based on fraction?
    else
        fraction = 0
    end

    for islice = 1:Nslices
        for iblade = 1:NBlade
            Rp[iblade,islice,:] .= RpL[iblade,islice,end] .+ fraction.*(RpU[iblade,islice,end].-RpL[iblade,islice,end])
            Tp[iblade,islice,:] .= TpL[iblade,islice,end] .+ fraction.*(TpU[iblade,islice,end].-TpL[iblade,islice,end])
            Zp[iblade,islice,:] .= ZpL[iblade,islice,end] .+ fraction.*(ZpU[iblade,islice,end].-ZpL[iblade,islice,end])
            Xp[iblade,islice,:] .= XpL[iblade,islice,end] .+ fraction.*(XpU[iblade,islice,end].-XpL[iblade,islice,end])
            Yp[iblade,islice,:] .= YpL[iblade,islice,end] .+ fraction.*(YpU[iblade,islice,end].-YpL[iblade,islice,end])
            alpha[iblade,islice,:] .= alphaL[iblade,islice,end] .+ fraction.*(alphaU[iblade,islice,end].-alphaL[iblade,islice,end])
            Vloc[iblade,islice,:] .= VlocL[iblade,islice,end] .+ fraction.*(VlocU[iblade,islice,end].-VlocL[iblade,islice,end])
            thetavec[iblade,:] .= thetavecL[iblade,end] .+ fraction.*(thetavecU[iblade,end].-thetavecL[iblade,end])
        end
        CP[islice,:] .= CPL[islice,end] .+ fraction.*(CPU[islice,end].-CPL[islice,end])
        cl[islice,:] .= clL[islice,end] .+ fraction.*(clU[islice,end].-clL[islice,end])
        cd_af[islice,:] .= cd_afL[islice,end] .+ fraction.*(cd_afU[islice,end].-cd_afL[islice,end])
        Re[islice,:] .= ReL[islice,end] .+ fraction.*(ReU[islice,end].-ReL[islice,end])
    end

    Fx_base = Fx_baseL[end] .+ fraction.*(Fx_baseU[end].-Fx_baseL[end])
    Fy_base = Fy_baseL[end] .+ fraction.*(Fy_baseU[end].-Fy_baseL[end])
    Fz_base = Fz_baseL[end] .+ fraction.*(Fz_baseU[end].-Fz_baseL[end])
    Mx_base = Mx_baseL[end] .+ fraction.*(Mx_baseU[end].-Mx_baseL[end])
    My_base = My_baseL[end] .+ fraction.*(My_baseU[end].-My_baseL[end])
    Mz_base = Mz_baseL[end] .+ fraction.*(Mz_baseU[end].-Mz_baseL[end])
    power = powerL[end] + fraction*(powerU[end]-powerL[end])
    power2 = power2L[end] + fraction*(power2U[end]-power2L[end])

    return CP,Rp,Tp,Zp,alpha,cl,cd_af,Vloc,Re,thetavec,ntheta,Fx_base,Fy_base,Fz_base,Mx_base,My_base,Mz_base,power,power2,nothing,z3Dnorm,delta,Xp,Yp
end
