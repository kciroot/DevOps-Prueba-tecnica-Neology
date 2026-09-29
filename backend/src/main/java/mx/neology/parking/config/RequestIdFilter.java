package mx.neology.parking.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Correlación de peticiones frontend → backend.
 *
 * <p>Origen del identificador, en orden de preferencia:
 * <ol>
 *   <li>{@code X-Request-ID}: lo genera nginx (stack local con Docker Compose).</li>
 *   <li>{@code X-Amzn-Trace-Id}: lo genera el ALB de AWS (se usa el valor {@code Root=}).</li>
 *   <li>Un UUID nuevo si no llega ninguno o no es seguro (evita log injection).</li>
 * </ol>
 * El valor se coloca en el MDC ({@code request_id} en cada línea de log JSON) y se devuelve en el
 * header {@code X-Request-ID} de la respuesta, visible en las DevTools del navegador.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Request-ID";
    public static final String AWS_TRACE_HEADER = "X-Amzn-Trace-Id";
    public static final String MDC_KEY = "request_id";

    private static final Logger log = LoggerFactory.getLogger(RequestIdFilter.class);
    private static final Pattern SAFE_ID = Pattern.compile("^[A-Za-z0-9._-]{8,64}$");

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String requestId = resolveRequestId(request.getHeader(HEADER),
                request.getHeader(AWS_TRACE_HEADER));
        MDC.put(MDC_KEY, requestId);
        response.setHeader(HEADER, requestId);
        try {
            chain.doFilter(request, response);
        } catch (IOException | ServletException | RuntimeException exception) {
            // Se registra aquí para que el error no controlado conserve el request_id en el log.
            log.error("Error no controlado en {} {}", request.getMethod(), request.getRequestURI(), exception);
            throw exception;
        } finally {
            MDC.remove(MDC_KEY);
        }
    }

    static String resolveRequestId(String requestIdHeader, String awsTraceHeader) {
        if (isSafe(requestIdHeader)) {
            return requestIdHeader;
        }
        String awsRoot = extractAwsTraceRoot(awsTraceHeader);
        if (isSafe(awsRoot)) {
            return awsRoot;
        }
        return UUID.randomUUID().toString();
    }

    /** "Root=1-67891233-abcdef012345678912345678;Sampled=1" → "1-67891233-abcdef012345678912345678". */
    private static String extractAwsTraceRoot(String header) {
        if (header == null) {
            return null;
        }
        for (String part : header.split(";")) {
            if (part.startsWith("Root=")) {
                return part.substring("Root=".length());
            }
        }
        return null;
    }

    private static boolean isSafe(String candidate) {
        return candidate != null && SAFE_ID.matcher(candidate).matches();
    }
}
