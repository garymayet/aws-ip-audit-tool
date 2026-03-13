Herramienta de auditoría diseñada para listar y rastrear todas las direcciones IP (públicas y privadas) en una cuenta de AWS. Permite identificar de manera rápida a qué servicio pertenece una IP específica y buscar coincidencias con IPs sospechosas.

## 🚀 Características

El script escanea **10 categorías de servicios** en busca de interfaces de red e IPs asociadas:
* **Cómputo:** EC2 (Instancias), Lambda.
* **Redes:** Elastic IPs, NAT Gateways, ENIs (Elastic Network Interfaces).
* **Contenedores:** EKS (Clústeres, Nodos, Fargate y NodeGroups).
* **Balanceo y Entrega:** Load Balancers (ALB, NLB, Classic), CloudFront.
* **Bases de Datos:** RDS.
* **Aceleración:** Global Accelerator / API Gateway.

## 🛠 Requisitos

* **AWS CLI** configurado con permisos de lectura (`ReadOnlyAccess` es suficiente para la mayoría de las consultas).
* **Bash** (Probado en AWS CloudShell y Linux).
* **Python 3** (Utilizado para procesar algunas salidas de JSON).

## 📋 Uso

### 1. Preparación
Dar permisos de ejecución al script:
```bash
chmod +x aws_ip_audit.sh
```

### 2. Ejecución básica

Escanear solo la región principal (recomendado para rapidez):

Bash

```
./aws_ip_audit.sh us-east-1
```

Escanear **todas** las regiones habilitadas en la cuenta (exhaustivo):

Bash

```
./aws_ip_audit.sh
```

### 3. Búsqueda de IPs específicas

El script tiene IPs sospechosas configuradas por defecto, pero puedes buscar otras usando una variable de entorno:

Bash

```
SEARCH_IPS="1.2.3.4,5.6.7.8" ./aws_ip_audit.sh us-east-1
```

## 📊 Resultados

El script genera dos archivos de salida:

1. **`aws_ip_audit_YYYYMMDD_HHMMSS.csv`**: Un inventario detallado de todas las IPs encontradas, incluyendo Región, Servicio, ID del Recurso y Descripción.
2. **`aws_ip_audit_summary_YYYYMMDD_HHMMSS.txt`**: Un resumen que indica explícitamente si se encontraron coincidencias con las IPs buscadas.

## ⚠️ Notas Importantes

- **Cuentas Múltiples:** Este script debe ejecutarse de forma independiente en cada cuenta de AWS vinculada al cliente (ej. `223397806318`, `176205639951`, y otras cuentas de Dev/Staging).
- **IPs Efímeras:** Si no se encuentra un match, es posible que el tráfico provenga de servicios efímeros (como Fargate o Lambda sin VPC) o de infraestructura fuera del alcance actual.

