#ifndef __CS_WALLDISTANCE_H__
#define __CS_WALLDISTANCE_H__

/*============================================================================
 * Compute the wall distance using the CDO framework
 *============================================================================*/

/*
  This file is part of Code_Saturne, a general-purpose CFD tool.

  Copyright (C) 1998-2015 EDF S.A.

  This program is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation; either version 2 of the License, or (at your option) any later
  version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  You should have received a copy of the GNU General Public License along with
  this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
  Street, Fifth Floor, Boston, MA 02110-1301, USA.
*/

/*----------------------------------------------------------------------------*/

/*----------------------------------------------------------------------------
 *  Local headers
 *----------------------------------------------------------------------------*/

#include "cs_base.h"
#include "cs_equation.h"

/*----------------------------------------------------------------------------*/

BEGIN_C_DECLS

/*============================================================================
 * Macro definitions
 *============================================================================*/

/*============================================================================
 * Type definitions
 *============================================================================*/

/*============================================================================
 * Public function prototypes
 *============================================================================*/

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the wall distance
 *
 * \param[in]   connect   pointer to a cs_cdo_connect_t structure
 * \param[in]   cdoq      pointer to a cs_cdo_quantities_t structure
 * \param[in]   eq        pointer to the associated cs_equation_t structure
 */
/*----------------------------------------------------------------------------*/

void
cs_walldistance_compute(const cs_cdo_connect_t      *connect,
                        const cs_cdo_quantities_t   *cdoq,
                        const cs_equation_t         *eq);

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Setup an new equation related to the wall distance
 *
 * \param[in]   eq          pointer to the associated cs_equation_t structure
 * \param[in]   wall_ml_id  id of the mesh location related to wall boundaries
 */
/*----------------------------------------------------------------------------*/

void
cs_walldistance_setup(cs_equation_t   *eq,
                      int              wall_ml_id);

/*----------------------------------------------------------------------------*/

END_C_DECLS

#endif /* __CS_CDO_WALLDIST_H__ */
