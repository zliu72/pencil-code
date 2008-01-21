;+
; NAME:
;       PC_READ_VAR
;
; PURPOSE:
;       Read var.dat, or other VAR files in any imaginable way!
;
;       Returns one or more fields from a snapshot (var) file generated by a
;       Pencil Code run.  Works for one or all processors. Can select subsets
;       of the data. And pretty much do everything you could dream with a var
;       file.
;
; CATEGORY:
;       Pencil Code, File I/O
;
; CALLING SEQUENCE:
;       pc_read_var, object=object, t=t,                          $
;                    varfile=varfile, datadir=datadir, proc=proc, $
;                    /nostats, /quiet, /help
; KEYWORD PARAMETERS:
;    datadir: specify the root data directory. Default is './data'   [string]
;       proc: specify a processor to get the data from. Default: ALL [integer]
;    varfile: name for the var file, default: 'var.dat'              [string]
;       ivar: a number to optionally append to the end of the        [integer]
;             varfile name.
;
;          t: returns the time of the snapshot                       [precision(mx)]
;
;     object: optional structure in which to return all the above    [structure]
;             (or those vars specified in 'variables')
;  variables: array of variable name to return                       [string(*)]
;
;  /additional: Load all variables stored in the files, PLUS any additional
;               variables specified with the variables=[] option.
;     /magic: call pc_magic_var to replace special variable names with their
;             functional equivalents
;
;   /trimxyz: remove ghost points from the x,y,z arrays that are returned
;   /trimall: remove ghost points from all returned variables and x,y,z arrays
;             - this is equivalent to wrapping each requested variable with
;                     pc_noghost(..., dim=dim)
;               pc_noghost will skip, i.e. do nothing to variables not
;               initially of size (dim.mx,dim.my,dim.mz)
;
;   /nostats: don't print any summary statistics for the returned fields
;     /stats: force printing of summary statistics even if quiet is set
;     /quiet: instruction not to print any 'helpful' information
;      /help: display this usage information, and exit
;
; EXAMPLES:
;       pc_read_var,obj=vars             ;; read all vars into VARS struct
;       pc_read_var,obj=vars,proc=5      ;; read only from data/proc5
;       pc_read_var,obj=vars,variables=['ss']
;                                        ;; read entropy into vars.ss
;       pc_read_var,obj=vars,variables=['bb'],/MAGIC
;                                        ;; calculate vars.bb from aa
;       pc_read_var,obj=vars,variables=['bb'],/MAGIC,/ADDITIONAL
;                                        ;; get vars.bb, vars.uu, vars.aa, etc.
;       pc_read_var,obj=vars,/bb         ;; shortcut for the above
;       pc_read_var,obj=vars,variables=['bb'],/MAGIC, /TRIMALL
;                                        ;; vars.bb without ghost points
;
; MODIFICATION HISTORY:
;       $Id: pc_read_var.pro,v 1.60 2008-01-21 15:43:11 ajohan Exp $
;       Written by: Antony J Mee (A.J.Mee@ncl.ac.uk), 27th November 2002
;
;-
pro pc_read_var, t=t,                                            $
    object=object, varfile=varfile_, associate=associate,        $
    variables=variables, tags=tags, magic=magic, bbtoo=bbtoo,    $
    trimxyz=trimxyz, trimall=trimall,                            $
    nameobject=nameobject,validate_variables=validate_variables, $
    dim=dim,param=param,param2=param2,ivar=ivar,                 $
    datadir=datadir,proc=proc,additional=additional,             $
    nxrange=nxrange,nyrange=nyrange,nzrange=nzrange,             $
    stats=stats,nostats=nostats,quiet=quiet,help=help,           $
    swap_endian=swap_endian,varcontent=varcontent,               $
    scalar=scalar,run2D=run2D

COMPILE_OPT IDL2,HIDDEN
;
; Use common block belonging to derivative routines etc. so we can
; set them up properly.
;
  common cdat,x,y,z,mx,my,mz,nw,ntmax,date0,time0
  common cdat_nonequidist,dx_1,dy_1,dz_1,dx_tilde,dy_tilde,dz_tilde,lequidist
  common pc_precision, zero, one
;
; Default settings
;
  default, magic, 0
  default, trimall, 0
  default, validate_variables, 1
;
; If no meaningful parameters are given show some help!
;
  if (keyword_set(help)) then begin
    doc_library,'pc_read_var'
    return
  endif
;
; Default data directory
;
  if (not keyword_set(datadir)) then datadir=pc_get_datadir()
;
; Name and path of varfile to read
;
  if (n_elements(ivar) eq 1) then begin
    default, varfile_, 'VAR'
    varfile=varfile_+strcompress(string(ivar),/remove_all)
  endif else begin
    default, varfile_, 'var.dat'
    varfile=varfile_
  endelse
;
; Get necessary dimensions quietly
;
  if (n_elements(dim) eq 0) then $
      pc_read_dim, object=dim, datadir=datadir, proc=proc, /quiet
  if (n_elements(param) eq 0) then $
      pc_read_param, object=param, dim=dim, datadir=datadir, /quiet
  if (n_elements(param2) eq 0 and magic) then begin
    spawn, 'ls '+datadir+'/param2.nml', exit_status=exit_status
    if (not exit_status) then begin
      pc_read_param, object=param2, /param2, dim=dim, datadir=datadir, /quiet
    endif else begin
      print, 'Could not find '+datadir+'/param2. This may give problems with'+ $
          ' magic variables.'
    endelse
  endif
;
; We know from start.in whether we have to read 2-D or 3-D data.
;
  default, run2D, 0
  if (param.lwrite_2d) then run2D=1
;
; Call pc_read_grid to make sure any derivative stuff is correctly set in the
; common block. Don't need the data for anything though.
;
  pc_read_grid, dim=dim, datadir=datadir, param=param, /quiet,swap_endian=swap_endian
;
; Read problem dimensions (global)...
;
  if (n_elements(proc) eq 1) then begin
    procdim=dim
  endif else begin
    pc_read_dim, object=procdim, datadir=datadir, proc=0, /quiet
  endelse
;
; ... and check pc_precision is set for all Pencil Code tools
;
  pc_set_precision, dim=dim, quiet=quiet
;
; Should ghost zones be returned?
;
  if (trimall) then trimxyz=1
;
; Local shorthand for some parameters
;
  nx=dim.nx
  ny=dim.ny
  nz=dim.nz
  nw=dim.nx*dim.ny*dim.nz
  mx=dim.mx
  my=dim.my
  mz=dim.mz
  mvar=dim.mvar
  precision=dim.precision
  mxloc=procdim.mx
  myloc=procdim.my
  mzloc=procdim.mz
;
; Number of processors over which to loop.
;
  if (n_elements(proc) eq 1) then begin
    nprocs=1
  endif else begin
    nprocs=dim.nprocx*dim.nprocy*dim.nprocz
  endelse
;
; Initialize / set default returns for ALL variables
;
  t=zero
  x=fltarr(mx)*one & y=fltarr(my)*one & z=fltarr(mz)*one
  dx=zero & dy=zero & dz=zero & deltay=zero
;
  if (n_elements(proc) ne 1) then begin
    xloc=fltarr(procdim.mx)*one
    yloc=fltarr(procdim.my)*one
    zloc=fltarr(procdim.mz)*one
  endif
;
;  Read meta data and set up variable/tag lists
;
  default, varcontent, pc_varcontent(datadir=datadir,dim=dim, $
                              param=param,quiet=quiet,scalar=scalar,run2D=run2D)
  totalvars=(size(varcontent))[1]-1
;
  if (n_elements(variables) ne 0) then begin
    if (keyword_set(additional)) then begin
      filevars=(varcontent[where((varcontent[*].idlvar ne 'dummy'))].idlvar)[1:*]
      variables=[filevars,variables]
      if (n_elements(tags) ne 0) then begin
        tags=[filevars,tags]
      endif
    endif
  endif else begin
    default,variables,(varcontent[where((varcontent[*].idlvar ne 'dummy'))].idlvar)[1:*]
  endelse
;
; Shortcut for getting magnetic field bb.
;
  default, bbtoo, 0
  if (bbtoo) then begin
    variables=[variables,'bb']
    magic=1
  endif
;
; Default tags are set equal to the variables.
;
  default, tags, variables
;
; Sanity check for variables and tags
;
  if (n_elements(variables) ne n_elements(tags)) then begin
    message, 'ERROR: variables and tags arrays differ in size'
  endif
;
; Apply "magic" variable transformations for derived quantities
;
  if (keyword_set(magic)) then $
      pc_magic_var,variables,tags,param=param, datadir=datadir
;
; Get a free unit number
;
  get_lun, file
;
; Prepare for read (build read command)
;
  res=''
  content=''
  for iv=1L,totalvars do begin
    if (n_elements(proc) eq 1) then begin
      res=res+','+varcontent[iv].idlvar
    endif else begin
      res=res+','+varcontent[iv].idlvarloc
    endelse
    content=content+', '+varcontent[iv].variable
;
; Initialise read buffers
;
    if (varcontent[iv].variable eq 'UNKNOWN') then $
        message, 'Unknown variable at position ' + str(iv)  $
        + ' needs declaring in varcontent.pro', /info
    if (execute(varcontent[iv].idlvar+'='+varcontent[iv].idlinit,0) ne 1) then $
        message, 'Error initialising ' + varcontent[iv].variable $
        +' - '+ varcontent[iv].idlvar, /info
    if (n_elements(proc) ne 1) then begin
      if (execute(varcontent[iv].idlvarloc+'='+varcontent[iv].idlinitloc,0) ne 1) then $
          message, 'Error initialising ' + varcontent[iv].variable $
          +' - '+ varcontent[iv].idlvarloc, /info
    endif
;
; For vector quantities skip the required number of elements of the f array
;
    iv=iv+varcontent[iv].skip
  endfor
;
; Display information about the files contents
;
  content = strmid(content,2)
  if ( not keyword_set(quiet) ) then $
      print,'File '+varfile+' contains: ', content
;
; Loop over processors
;
  for i=0,nprocs-1 do begin
    if (n_elements(proc) eq 1) then begin
      ; Build the full path and filename
      filename=datadir+'/proc'+str(proc)+'/'+varfile
    endif else begin
      filename=datadir+'/proc'+str(i)+'/'+varfile
      if (not keyword_set(quiet)) then $
          print, 'Loading chunk ', strtrim(str(i+1)), ' of ', $
          strtrim(str(nprocs)), ' (', $
          strtrim(datadir+'/proc'+str(i)+'/'+varfile), ')...'
      pc_read_dim, object=procdim, datadir=datadir, proc=i, /quiet
    endelse
;
; Check for existance and read the data
;
    dummy=findfile(filename, COUNT=countfile)
    if (not countfile gt 0) then begin
      message, 'ERROR: cannot find file '+ filename
    endif
;
; Setup the coordinates mappings from the processor
; to the full domain.
;
    if (n_elements(proc) eq 1) then begin
    endif else begin
;
;  Don't overwrite ghost zones of processor to the left (and
;  accordingly in y and z direction makes a difference on the
;  diagonals)
;
      if (procdim.ipx eq 0L) then begin
        i0x=0L
        i1x=i0x+procdim.mx-1L
        i0xloc=0L
        i1xloc=procdim.mx-1L
      endif else begin
        i0x=procdim.ipx*procdim.nx+procdim.nghostx
        i1x=i0x+procdim.mx-1L-procdim.nghostx
        i0xloc=procdim.nghostx & i1xloc=procdim.mx-1L
      endelse
;
      if (procdim.ipy eq 0L) then begin
        i0y=0L
        i1y=i0y+procdim.my-1L
        i0yloc=0L
        i1yloc=procdim.my-1L
      endif else begin
        i0y=procdim.ipy*procdim.ny+procdim.nghosty
        i1y=i0y+procdim.my-1L-procdim.nghosty
        i0yloc=procdim.nghosty
        i1yloc=procdim.my-1L
      endelse
;
      if (procdim.ipz eq 0L) then begin
        i0z=0L
        i1z=i0z+procdim.mz-1L
        i0zloc=0L
        i1zloc=procdim.mz-1L
      endif else begin
        i0z=procdim.ipz*procdim.nz+procdim.nghostz
        i1z=i0z+procdim.mz-1L-procdim.nghostz
        i0zloc=procdim.nghostz
        i1zloc=procdim.mz-1L
      endelse
;;
;; Skip this processor if it makes no contribution to the requested
;; subset of the domain.
;;
;       if (n_elements(nxrange)==2) then begin
;         if ((i0x gt nxrange[1]+procdim.nghostx) or (i1x lt nxrange[0]+procdim.nghostx)) then continue
;         ix0=max([ix0-(nxrange[0]+procdim.nghostx),0L]
;         ix1=min([ix1-(nxrange[0]+procdim.nghostx),ix0+(nxrange[1]-nxrange[0])]
;       endif
;       if (n_elements(nyrange)==2) then begin
;         if ((i0y gt nyrange[1]+procdim.nghosty) or (i1y lt nyrange[0]+procdim.nghosty)) then continue
;       endif
;       if (n_elements(nzrange)==2) then begin
;         if ((i0z gt nzrange[1]+procdim.nghostz) or (i1z lt nzrange[0]+procdim.nghostz)) then continue
;       endif
    endelse
;
; Open a varfile and read some data!
;
    close,file
    openr,file, filename, /f77, swap_endian=swap_endian
    if (not keyword_set(associate)) then begin
      if (execute('readu,file'+res) ne 1) then $
          message, 'Error reading: ' + 'readu,' + str(file) + res
    endif else begin
      message, 'Associate behaviour not implemented here yet'
    endelse
;
    if (n_elements(proc) eq 1) then begin
      if (param.lshear) then begin
        readu, file, t, x, y, z, dx, dy, dz, deltay
      endif else begin
        readu, file, t, x, y, z, dx, dy, dz
      endelse
    endif else begin
      if (param.lshear) then begin
        readu, file, t, xloc, yloc, zloc, dx, dy, dz, deltay
      endif else begin
        readu, file, t, xloc, yloc, zloc, dx, dy, dz
      endelse
;
      x[i0x:i1x] = xloc[i0xloc:i1xloc]
      y[i0y:i1y] = yloc[i0yloc:i1yloc]
      z[i0z:i1z] = zloc[i0zloc:i1zloc]
;
; Loop over variables.
;
      for iv=1L,totalvars do begin
        if (varcontent[iv].variable eq 'UNKNOWN') then continue
;
; For 2-D run with lwrite_2d=T we only need to read 2-D data.
;
        if (keyword_set(run2D)) then begin
          if (nx eq 1) then begin
; 2-D run in (y,z) plane.
            cmd =   varcontent[iv].idlvar $
                + "[dim.l1,i0y:i1y,i0z:i1z,*,*]=" $
                + varcontent[iv].idlvarloc $
                +"[i0yloc:i1yloc,i0zloc:i1zloc,*,*]"
          endif else if (ny eq 1) then begin
; 2-D run in (x,z) plane.
            cmd =   varcontent[iv].idlvar $
                + "[i0x:i1x,dim.m1,i0z:i1z,*,*]=" $
                + varcontent[iv].idlvarloc $
                +"[i0xloc:i1xloc,i0zloc:i1zloc,*,*]"
          endif else begin
; 2-D run in (x,y) plane.
            cmd =   varcontent[iv].idlvar $
                + "[i0x:i1x,i0y:i1y,dim.n1,*,*]=" $
                + varcontent[iv].idlvarloc $
                +"[i0xloc:i1xloc,i0yloc:i1yloc,*,*]"
          endelse 
        endif else begin
;
; Regular 3-D run.
;        
          cmd =   varcontent[iv].idlvar $
              + "[i0x:i1x,i0y:i1y,i0z:i1z,*,*]=" $
              + varcontent[iv].idlvarloc $
              +"[i0xloc:i1xloc,i0yloc:i1yloc,i0zloc:i1zloc,*,*]"
        endelse
        if (execute(cmd) ne 1) then $
            message, 'Error combining data for ' + varcontent[iv].variable
;
; For vector quantities skip the required number of elements
;
        iv=iv+varcontent[iv].skip
      endfor
;
    endelse
;
    if (not keyword_set(associate)) then begin
      close,file
      free_lun,file
    endif
  endfor
;
; Tidy memory a little
;
  if (n_elements(proc) ne 1) then begin
    undefine,xloc
    undefine,yloc
    undefine,zloc
    for iv=1L,totalvars do begin
      undefine, varcontent[iv].idlvarloc
    endfor
  endif
;
; Check variables one at a time and skip the ones that give errors.
; This way the program can still return the other variables, instead
; of dying with an error. One can turn off this option off to decrease
; execution time.
;
  if (validate_variables) then begin
    skipvariable=make_array(n_elements(variables),/INT,value=0)
    for iv=0,n_elements(variables)-1 do begin
      res=execute(tags[iv]+'='+variables[iv])
      if (not res) then begin
        if (not keyword_set(quiet)) then $
            print,"% Skipping: "+tags[iv]+" -> "+variables[iv]
        skipvariable[iv]=1
      endif
    endfor
    if (min(skipvariable) ne 0) then return
    if (max(skipvariable) eq 1) then begin
      variables=variables[where(skipvariable eq 0)]
      tags=tags[where(skipvariable eq 0)]
    endif
  endif
;
; Save changs to the variables array (but don't include the effect of /TRIMALL)
;
  variables_in=variables
;
; Trim x, y and z if requested.
;
  if (keyword_set(trimxyz)) then begin
    xyzstring="x[dim.l1:dim.l2],y[dim.m1:dim.m2],z[dim.n1:dim.n2]"
  endif else begin
    xyzstring="x,y,z"
  endelse
;
; Remove ghost zones if requested.
;
  if (keyword_set(trimall)) then variables = 'pc_noghost('+variables+',dim=dim)'
;
; Make structure out of the variables.
;
  makeobject = "object = "+ $
      "CREATE_STRUCT(name=objectname,['t','x','y','z','dx','dy','dz'" + $
      arraytostring(tags,QUOTE="'") + "],t,"+xyzstring+",dx,dy,dz" + $
      arraytostring(variables) + ")"
;
; Execute command to make the structure.
;
  if (execute(makeobject) ne 1) then begin
    message, 'ERROR evaluating variables: '+makeobject
    undefine, object
  endif
;
; If requested print a summary (actually the default - unless being quiet.)
;
  if (keyword_set(stats) or $
     (not (keyword_set(nostats) or keyword_set(quiet)))) then begin
    if (not keyword_set(quiet)) then print, ''
    if (not keyword_set(quiet)) then print, 'VARIABLE SUMMARY:'
    pc_object_stats, object, dim=dim, trim=trimall, quiet=quiet
    print,' t = ', t
  endif
;
end
