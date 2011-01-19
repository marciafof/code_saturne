
import sys,traceback,os
import FSI_ORB__POA
import calcium
import dsccalcium
import SALOME
import linecache
import shutil

sys.path=sys.path+['### TO BE MODIFIED - asterpyt ###']
import aster
import Accas
import Cata.cata
from Execution.E_SUPERV import SUPERV

aster_dir="### TO BE MODIFIED - asterdir ###"

try:
  import numpy
except:
  numpy=None

#DEFS

#ENDDEF

class FSI_ASTER(FSI_ORB__POA.FSI_ASTER,dsccalcium.PyDSCComponent,SUPERV):
  '''
     To be identified as a SALOME component this Python class
     must have the same name as the component, inherit omniorb
     class FSI_ORB__POA.FSI_ASTER and DSC class dsccalcium.PyDSCComponent
     that implements DSC API.
  '''
  def __init__ ( self, orb, poa, contID, containerName, instanceName, interfaceName ):
    dsccalcium.PyDSCComponent.__init__(self, orb, poa,contID,containerName,instanceName,interfaceName)
    self.argv=['salome_aster','-memjeveux','64','-mxmemdy','64','-rep_outils','### TO BE MODIFIED - asteroutil ###']
    #modif pour aster 9.0
    if hasattr(self,"init_timer"):
      self.init_timer()
    #fin modif pour aster 9.0
    if os.path.exists(os.path.join(aster_dir,"elements")):
      shutil.copyfile(os.path.join(aster_dir,"elements"),"elem.1")
    else:
      shutil.copyfile(os.path.join(aster_dir,"catobj","elements"),"elem.1")

  def init_service(self,service):
    if service == "op0103":
       #initialization CALCIUM ports IN
       calcium.create_calcium_port(self.proxy,"NB_FOR","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"NB_DYN","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"COONOD","CALCIUM_double","IN","I")
       calcium.create_calcium_port(self.proxy,"COOFAC","CALCIUM_double","IN","I")
       calcium.create_calcium_port(self.proxy,"COLNOD","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"COLFAC","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"FORAST","CALCIUM_double","IN","I")
       calcium.create_calcium_port(self.proxy,"NBPDTM","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"NBSSIT","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"EPSILO","CALCIUM_double","IN","I")
       calcium.create_calcium_port(self.proxy,"ICVAST","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"ISYNCP","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"NTCHRO","CALCIUM_integer","IN","I")
       calcium.create_calcium_port(self.proxy,"TTINIT","CALCIUM_double","IN","I")
       calcium.create_calcium_port(self.proxy,"PDTREF","CALCIUM_double","IN","I")
       calcium.create_calcium_port(self.proxy,"DTCALC","CALCIUM_double","IN","I")
       #initialization CALCIUM ports OUT
       calcium.create_calcium_port(self.proxy,"DEPAST","CALCIUM_double","OUT","I")
       calcium.create_calcium_port(self.proxy,"VITAST","CALCIUM_double","OUT","I")
       calcium.create_calcium_port(self.proxy,"DTAST","CALCIUM_double","OUT","I")
       return True 
    return False


  def op0103(self,jdc):
    self.beginService("FSI_ASTER.op0103")
    self.jdc=Cata.cata.JdC(procedure=jdc,cata=Cata.cata,nom="Salome",context_ini={"jdc":jdc,"component":self.proxy.ptr()})
    j=self.jdc
    #modif pour aster 9.0
    if hasattr(self,"init_timer"):
      j.timer = self.timer
    #fin modif pour aster 9.0

    # On compile le texte Python
    j.compile()

    #modif pour aster 9.0
    # On initialise les tops de mesure globale de temps d'execution du jdc
    if hasattr(self,"init_timer"):
       j.cpu_user=os.times()[0]
       j.cpu_syst=os.times()[1]
    #fin modif pour aster 9.0

    if not j.cr.estvide():
       msg="ERREUR DE COMPILATION DANS ACCAS - INTERRUPTION"
       self.MESSAGE(msg)
       print ">> JDC.py : DEBUT RAPPORT"
       print j.cr
       print ">> JDC.py : FIN RAPPORT"
       j.supprime()
       sys.stdout.flush()
       raise SALOME.SALOME_Exception(SALOME.ExceptionStruct(SALOME.BAD_PARAM,msg+'\n'+str(j.cr),"FSI_ASTER.py",0))

    #surcharge des arguments de la ligne de commande (defaut stocke dans le composant) par un eventuel port de nom argv
    try:
      self.argv=self.argv+argv.split()
    except:
      pass

    #initialisation des arguments de la ligne de commande (remplace la methode initexec de B_JDC.py)
    aster.argv(self.argv)
    aster.init(CONTEXT.debug)
    j.setmode(1)
    j.ini=1

    try:
      j.exec_compile()
    except:
      sys.stdout.flush()
      exc_typ,exc_val,exc_fr=sys.exc_info()
      l=traceback.format_exception(exc_typ,exc_val,exc_fr)
      raise SALOME.SALOME_Exception(SALOME.ExceptionStruct(SALOME.BAD_PARAM,"".join(l),"FSI_ASTER.py",0))

    ier=0
    if not j.cr.estvide():
       msg="ERREUR A L'INTERPRETATION DANS ACCAS - INTERRUPTION"
       self.MESSAGE(msg)
       ier=1
       print ">> JDC.py : DEBUT RAPPORT"
       print j.cr
       print ">> JDC.py : FIN RAPPORT"
       sys.stdout.flush()
       raise SALOME.SALOME_Exception(SALOME.ExceptionStruct(SALOME.BAD_PARAM,msg+'\n'+str(j.cr), "FSI_ASTER.py",0))

    if j.par_lot == 'NON':
       print "FIN EXECUTION"
       err=calcium.cp_fin(self.proxy,calcium.CP_ARRET)
       #retour sans erreur (il faut pousser les variables de sortie)
       sys.stdout.flush()
       self.endService("FSI_ASTER.op0103")
       return 

    # Verification de la validite du jeu de commande
    cr=j.report()
    if not cr.estvide():
       msg="ERREUR A LA VERIFICATION SYNTAXIQUE - INTERRUPTION"
       self.MESSAGE(msg)
       print ">> JDC.py : DEBUT RAPPORT"
       print cr
       print ">> JDC.py : FIN RAPPORT"
       sys.stdout.flush()
       raise SALOME.SALOME_Exception(SALOME.ExceptionStruct(SALOME.BAD_PARAM,msg+'\n'+str(cr),"FSI_ASTER.py",0))

    j.set_par_lot("NON")
    try:
       j.BuildExec()
       ier=0
       if not j.cr.estvide():
          msg="ERREUR A L'EXECUTION - INTERRUPTION"
          self.MESSAGE(msg)
          ier=1
          print ">> JDC.py : DEBUT RAPPORT"
          print j.cr
          print ">> JDC.py : FIN RAPPORT"
          sys.stdout.flush()
          raise SALOME.SALOME_Exception(SALOME.ExceptionStruct(SALOME.BAD_PARAM,msg+'\n'+str(j.cr),"FSI_ASTER.py",0))
       else:
         #retour sans erreur (il faut pousser les variables de sortie)
         err=calcium.cp_fin(self.proxy,calcium.CP_ARRET)
         sys.stdout.flush()
         self.endService("FSI_ASTER.op0103")
         return 
    except :
      self.MESSAGE("ERREUR INOPINEE - INTERRUPTION")
      sys.stdout.flush()
      exc_typ,exc_val,exc_fr=sys.exc_info()
      l=traceback.format_exception(exc_typ,exc_val,exc_fr)
      raise SALOME.SALOME_Exception(SALOME.ExceptionStruct(SALOME.BAD_PARAM,"".join(l),"FSI_ASTER.py",0))

